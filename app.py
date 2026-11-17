#!/usr/bin/env python3
"""Servidor local de ferramentas PDF (catálogo mapeado com REA)."""

from __future__ import annotations

import argparse
import io
import os
import re
import shutil
import subprocess
import time
import unicodedata
import uuid
import zipfile
from pathlib import Path

from flask import Flask, jsonify, render_template, request, send_from_directory
from werkzeug.exceptions import HTTPException
from PIL import Image, ImageOps
from pypdf import PasswordType, PdfReader, PdfWriter
from pypdf.constants import UserAccessPermissions as UAP
from pypdf.generic import RectangleObject
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
UPLOAD_DIR = DATA_DIR / "uploads"
OUTPUT_DIR = DATA_DIR / "outputs"


def _configure_bundled_windows_tools() -> None:
    """Expose the portable Windows tools without changing the system PATH."""
    if os.name != "nt":
        return

    tools_dir = BASE_DIR / "vendor" / "windows"
    bundled_paths = (
        tools_dir / "ghostscript" / "bin",
        tools_dir / "poppler" / "bin",
        tools_dir / "tesseract",
        tools_dir / "libreoffice" / "program",
    )
    existing = [str(path) for path in bundled_paths if path.is_dir()]
    if existing:
        os.environ["PATH"] = os.pathsep.join(existing + [os.environ.get("PATH", "")])

    tessdata = tools_dir / "tesseract" / "tessdata"
    if tessdata.is_dir():
        os.environ.setdefault("TESSDATA_PREFIX", str(tools_dir / "tesseract"))


_configure_bundled_windows_tools()

for _d in (UPLOAD_DIR, OUTPUT_DIR):
    _d.mkdir(parents=True, exist_ok=True)

MAX_FILES = 60
MAX_TOTAL_BYTES = 250 * 1024 * 1024
JOB_TTL = 2 * 60 * 60
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}
OFFICE_EXTS = {
    ".doc", ".docx", ".odt", ".rtf", ".txt",
    ".ppt", ".pptx", ".odp", ".xls", ".xlsx", ".ods", ".csv", ".html",
}

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_TOTAL_BYTES
app.config["JSON_SORT_KEYS"] = False

_last_cleanup = 0.0
_watermark_font = "Helvetica-Bold"
for _path, _name in (
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "DejaVu-Bold"),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "DejaVu"),
):
    try:
        if os.path.exists(_path):
            pdfmetrics.registerFont(TTFont(_name, _path))
    except Exception:
        pass
if "DejaVu-Bold" in pdfmetrics.getRegisteredFontNames():
    _watermark_font = "DejaVu-Bold"


class UserError(Exception):
    pass


# --------------------------------------------------------------------------- #
# utilidades
# --------------------------------------------------------------------------- #

def safe_stem(name: str) -> str:
    stem = Path(name or "").stem
    stem = unicodedata.normalize("NFKD", stem).encode("ascii", "ignore").decode()
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", stem).strip("._-")
    return (stem or "arquivo")[:80]


def job_dir(job: str, kind: str) -> Path:
    return (UPLOAD_DIR if kind == "up" else OUTPUT_DIR) / job


def new_job() -> str:
    job = uuid.uuid4().hex
    job_dir(job, "up").mkdir(parents=True, exist_ok=True)
    job_dir(job, "out").mkdir(parents=True, exist_ok=True)
    return job


def cleanup_old(force: bool = False) -> None:
    global _last_cleanup
    now = time.time()
    if not force and now - _last_cleanup < 120:
        return
    _last_cleanup = now
    for base in (UPLOAD_DIR, OUTPUT_DIR):
        for child in base.iterdir():
            try:
                if now - child.stat().st_mtime > JOB_TTL:
                    shutil.rmtree(child, ignore_errors=True)
            except OSError:
                pass


def run(cmd: list[str], timeout: int = 300, home: Path | None = None) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    if home is not None:
        env["HOME"] = str(home)
    command = list(cmd)
    if os.name == "nt" and Path(command[0]).name.lower() == "gs":
        bundled_gs = BASE_DIR / "vendor" / "windows" / "ghostscript" / "bin" / "gswin64c.exe"
        if bundled_gs.is_file():
            command[0] = str(bundled_gs)
    try:
        proc = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, env=env
        )
    except FileNotFoundError:
        packages = {
            "gs": "ghostscript",
            "pdftoppm": "poppler-utils",
            "pdftotext": "poppler-utils",
            "tesseract": "tesseract-ocr",
            "soffice": "libreoffice-nogui",
        }
        package = packages.get(Path(cmd[0]).name)
        hint = f" (pacote {package})" if package else ""
        raise UserError(
            f"Programa necessário não encontrado: {cmd[0]}{hint}. "
            "Execute ./install-deps.sh ou instale o pacote no sistema."
        )
    except subprocess.TimeoutExpired:
        raise UserError("O processamento demorou demais e foi interrompido.")
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip().splitlines()
        detail = detail[-1] if detail else "erro desconhecido"
        raise UserError(f"Falha ao processar ({cmd[0]}): {detail}")
    return proc


def read_pdf(path: Path, password: str = "") -> PdfReader:
    with open(path, "rb") as fh:
        head = fh.read(1024)
    if b"%PDF-" not in head:
        raise UserError(f'"{path.name}" não parece ser um PDF válido.')
    try:
        reader = PdfReader(str(path))
        if reader.is_encrypted:
            result = reader.decrypt(password or "")
            if result == PasswordType.NOT_DECRYPTED:
                raise UserError(
                    "O PDF está protegido por senha. Use a ferramenta "
                    '"Desbloquear PDF" primeiro.'
                )
        return reader
    except UserError:
        raise
    except Exception as exc:
        raise UserError(f"Não foi possível ler o PDF: {exc}")


def save_uploads(job: str, only_exts: set[str] | None = None) -> list[dict]:
    files = [f for f in request.files.getlist("files") if f and f.filename]
    if not files:
        raise UserError("Selecione ao menos um arquivo.")
    if len(files) > MAX_FILES:
        raise UserError(f"Envie no máximo {MAX_FILES} arquivos por vez.")
    saved = []
    dest = job_dir(job, "up")
    for idx, storage in enumerate(files):
        original = Path(storage.filename).name
        ext = Path(original).suffix.lower()
        if only_exts is not None and ext not in only_exts:
            raise UserError(f'Formato não aceito nesta ferramenta: "{original}".')
        filename = f"{idx:03d}_{safe_stem(original)}{ext}"
        path = dest / filename
        storage.save(path)
        if path.stat().st_size == 0:
            raise UserError(f'O arquivo "{original}" está vazio.')
        saved.append({"name": original, "path": path, "ext": ext})
    return saved


def parse_ranges(spec: str, total: int, allow_empty: bool = False) -> list[int]:
    """Converte "1-3,5,7-" em índices base 0, preservando a ordem."""
    spec = (spec or "").replace(" ", "")
    if not spec:
        if allow_empty:
            return list(range(total))
        raise UserError("Informe as páginas (ex.: 1-3, 5).")
    result: list[int] = []
    for part in spec.split(","):
        if not part:
            continue
        try:
            if "-" in part:
                a, b = part.split("-", 1)
                start = int(a) if a else 1
                end = int(b) if b else total
                if start < 1 or end > total or start > end:
                    raise ValueError
                result.extend(range(start - 1, end))
            else:
                page = int(part)
                if page < 1 or page > total:
                    raise ValueError
                result.append(page - 1)
        except ValueError:
            raise UserError(
                f'Intervalo de páginas inválido: "{part}". '
                f"O documento tem {total} página(s)."
            )
    if not result:
        raise UserError("Nenhuma página selecionada.")
    return result


def deliver(job: str, base: str, items: list[tuple[str, Path]]) -> dict:
    """Copia o resultado único (ou empacota vários) na pasta de saída."""
    out = job_dir(job, "out")
    out.mkdir(parents=True, exist_ok=True)
    if len(items) == 1:
        name, path = items[0]
        final = out / name
        if path.resolve() != final.resolve():
            shutil.copyfile(path, final)
    else:
        name = f"{base}_resultado.zip"
        final = out / name
        used: set[str] = set()
        with zipfile.ZipFile(final, "w", zipfile.ZIP_DEFLATED) as zf:
            for friendly, path in items:
                candidate = friendly
                n = 2
                while candidate in used:
                    stem, ext = os.path.splitext(friendly)
                    candidate = f"{stem}_{n}{ext}"
                    n += 1
                used.add(candidate)
                zf.write(path, candidate)
    return {
        "name": name,
        "url": f"/files/{job}/{name}",
        "size": final.stat().st_size,
    }


def gs_compress(src: Path, dst: Path, level: str) -> None:
    settings = {"low": "/printer", "medium": "/ebook", "high": "/screen"}
    setting = settings.get(level, "/ebook")
    cmd = [
        "gs", "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.7",
        "-dNOPAUSE", "-dQUIET", "-dBATCH", "-dSAFER",
        "-dDetectDuplicateImages=true", "-dCompressFonts=true",
        f"-dPDFSETTINGS={setting}",
    ]
    if level == "high":
        cmd += [
            "-dDownsampleColorImages=true", "-dDownsampleGrayImages=true",
            "-dColorImageResolution=96", "-dGrayImageResolution=96",
            "-dMonoImageResolution=300",
            "-dColorImageDownsampleType=/Bicubic",
            "-dGrayImageDownsampleType=/Bicubic",
        ]
    cmd += [f"-sOutputFile={dst}", str(src)]
    run(cmd, timeout=600)
    if not dst.exists() or dst.stat().st_size == 0:
        raise UserError("Não foi possível comprimir este PDF.")


def gs_repair(src: Path, dst: Path) -> None:
    cmd = [
        "gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER",
        "-sDEVICE=pdfwrite", "-dPDFSTOPONERROR=false",
        "-dCompatibilityLevel=1.7", f"-sOutputFile={dst}", str(src),
    ]
    try:
        run(cmd, timeout=600)
    except UserError:
        raise UserError(
            "Não foi possível reconstruir este PDF. "
            "O arquivo pode estar danificado demais."
        )
    if not dst.exists() or dst.stat().st_size == 0:
        raise UserError("Não foi possível reconstruir este PDF.")
    try:
        reader = PdfReader(str(dst))
        if len(reader.pages) < 1:
            raise ValueError("sem páginas")
    except Exception:
        raise UserError("O PDF está danificado demais para ser reconstruído.")


def overlay_for(page_size: tuple[float, float], painter) -> object:
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=page_size)
    painter(c)
    c.showPage()
    c.save()
    buf.seek(0)
    return PdfReader(buf).pages[0]


def make_watermark(
    src: Path, dst: Path, text: str, opacity: float, position: str,
    size: float, rotation: float, color: str, tiled: bool,
) -> None:
    writer = PdfWriter(clone_from=str(src))
    rgb = HexColor(re.sub(r"^#", "#", color or "#ff0000"))
    lines = [ln for ln in text.splitlines()] or [text]

    for page in writer.pages:
        if page.rotation:
            page.transfer_rotation_to_content()
        w = float(page.mediabox.width)
        h = float(page.mediabox.height)

        def paint(c, w=w, h=h):
            c.setFillColor(rgb)
            c.setFillAlpha(max(0.03, min(opacity, 1.0)))
            c.setFont(_watermark_font, size)
            leading = size * 1.25
            if tiled:
                step_x = max(220.0, size * max(len(text), 6) * 0.62)
                step_y = max(120.0, size * 2.0)
                for yy in range(0, int(h) + int(step_y), int(step_y)):
                    for xx in range(-int(w), int(w * 2), int(step_x)):
                        c.saveState()
                        c.translate(xx, yy)
                        c.rotate(rotation if rotation else 35)
                        c.drawCentredString(0, 0, text.strip() or " ")
                        c.restoreState()
                return
            margin = 36
            if position == "center":
                x, y, align = w / 2, h / 2, "center"
            elif position == "top-left":
                x, y, align = margin, h - margin, "left"
            elif position == "top-right":
                x, y, align = w - margin, h - margin, "right"
            elif position == "bottom-left":
                x, y, align = margin, margin, "left"
            elif position == "bottom-right":
                x, y, align = w - margin, margin, "right"
            elif position == "top-center":
                x, y, align = w / 2, h - margin, "center"
            else:  # bottom-center
                x, y, align = w / 2, margin, "center"
            c.saveState()
            if position == "center":
                c.translate(x, y)
                c.rotate(rotation)
                start = (len(lines) - 1) * leading / 2
                for i, line in enumerate(lines):
                    c.drawCentredString(0, start - i * leading, line)
            else:
                c.translate(x, y)
                c.rotate(rotation)
                for i, line in enumerate(lines):
                    if align == "center":
                        c.drawCentredString(0, -i * leading, line)
                    elif align == "right":
                        c.drawRightString(0, -i * leading, line)
                    else:
                        c.drawString(0, -i * leading, line)
            c.restoreState()

        page.merge_page(overlay_for((w, h), paint))

    with open(dst, "wb") as fh:
        writer.write(fh)


def add_page_numbers(
    src: Path, dst: Path, position: str, fmt: str, size: float,
    start: int, color: str, margin: float,
) -> None:
    writer = PdfWriter(clone_from=str(src))
    total = len(writer.pages)
    rgb = HexColor(color or "#444444")

    for idx, page in enumerate(writer.pages):
        if page.rotation:
            page.transfer_rotation_to_content()
        w = float(page.mediabox.width)
        h = float(page.mediabox.height)
        number = start + idx
        label = fmt.replace("{n}", str(number)).replace("{total}", str(total))

        def paint(c, w=w, h=h, label=label):
            c.setFillColor(rgb)
            c.setFont(_watermark_font, size)
            if position == "bottom-center":
                c.drawCentredString(w / 2, margin, label)
            elif position == "bottom-right":
                c.drawRightString(w - margin, margin, label)
            elif position == "bottom-left":
                c.drawString(margin, margin, label)
            elif position == "top-center":
                c.drawCentredString(w / 2, h - margin - size, label)
            elif position == "top-right":
                c.drawRightString(w - margin, h - margin - size, label)
            else:
                c.drawString(margin, h - margin - size, label)

        page.merge_page(overlay_for((w, h), paint))

    with open(dst, "wb") as fh:
        writer.write(fh)


def convert_office(src: Path, out_dir: Path, target: str = "pdf") -> Path:
    profile = out_dir / f"lo_profile_{uuid.uuid4().hex[:8]}"
    profile.mkdir(parents=True, exist_ok=True)
    cmd = [
        "soffice", "--headless", "--nologo",
        f"-env:UserInstallation={profile.resolve().as_uri()}",
    ]
    if target == "docx":
        cmd += ["--infilter=writer_pdf_import", "--convert-to", "docx:MS Word 2007 XML"]
    else:
        cmd += ["--convert-to", "pdf"]
    cmd += ["--outdir", str(out_dir), str(src)]
    run(cmd, timeout=300, home=out_dir)
    candidates = sorted(
        (p for p in out_dir.iterdir()
         if p.is_file() and p.suffix.lower() == f".{target}" and p.stem == src.stem),
        key=lambda p: p.stat().st_mtime,
    )
    if not candidates:
        raise UserError("A conversão não gerou nenhum arquivo.")
    return candidates[-1]


# --------------------------------------------------------------------------- #
# rotas
# --------------------------------------------------------------------------- #

@app.before_request
def _cleanup():
    cleanup_old()


@app.get("/")
def index():
    langs = ["eng"]
    try:
        proc = subprocess.run(
            ["tesseract", "--list-langs"], capture_output=True, text=True, timeout=10
        )
        found = [
            ln.strip() for ln in proc.stdout.splitlines()
            if ln.strip() and " " not in ln and ln.strip() != "osd"
        ]
        if found:
            langs = found
    except Exception:
        pass
    return render_template("index.html", langs=langs)


@app.get("/rea/evidence-summary.json")
def rea_evidence():
    return send_from_directory(BASE_DIR / "rea", "evidence-summary.json")


@app.get("/files/<job>/<path:name>")
def download(job: str, name: str):
    if not re.fullmatch(r"[0-9a-f]{32}", job):
        return jsonify(ok=False, error="Arquivo não encontrado."), 404
    directory = job_dir(job, "out")
    return send_from_directory(directory, name, as_attachment=True, download_name=name)


@app.errorhandler(413)
def too_large(_exc):
    return jsonify(ok=False, error="Arquivo grande demais (limite de 250 MB)."), 413


@app.errorhandler(UserError)
def user_error(exc: UserError):
    return jsonify(ok=False, error=str(exc)), 400


@app.errorhandler(HTTPException)
def http_error(exc: HTTPException):
    return jsonify(ok=False, error=exc.description or exc.name), exc.code or 500


@app.errorhandler(Exception)
def internal_error(exc: Exception):
    app.logger.exception("Erro inesperado")
    return jsonify(ok=False, error=f"Erro inesperado: {exc}"), 500


@app.post("/api/merge")
def api_merge():
    job = new_job()
    saved = save_uploads(job)
    if len(saved) < 2:
        raise UserError("Envie ao menos 2 PDFs para unir.")
    writer = PdfWriter()
    for item in saved:
        reader = read_pdf(item["path"])
        writer.append(reader, import_outline=False)
    base = safe_stem(saved[0]["name"])
    dst = job_dir(job, "up") / "unido.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_unido.pdf", dst)]),
        note=f"{len(saved)} arquivos unidos em {len(writer.pages)} páginas.",
    )


@app.post("/api/split")
def api_split():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    total = len(reader.pages)
    base = safe_stem(saved[0]["name"])
    mode = request.form.get("mode", "each")
    work = job_dir(job, "up") / "partes"
    work.mkdir(exist_ok=True)
    items: list[tuple[str, Path]] = []

    def write_part(indices: list[int], label: str) -> None:
        writer = PdfWriter()
        for i in indices:
            writer.add_page(reader.pages[i])
        path = work / f"{label}.pdf"
        with open(path, "wb") as fh:
            writer.write(fh)
        items.append((f"{base}_{label}.pdf", path))

    if mode == "ranges":
        spec = (request.form.get("ranges") or "").replace(" ", "")
        parts = [p for p in spec.split(",") if p]
        if not parts:
            raise UserError("Informe os intervalos (ex.: 1-3, 4-6).")
        for part in parts:
            indices = sorted(set(parse_ranges(part, total)))
            label = "pagina_" + part.replace("-", "_")
            write_part(indices, label)
    elif mode == "fixed":
        try:
            every = int(request.form.get("every", "2"))
        except ValueError:
            raise UserError("Informe um número válido de páginas.")
        if every < 1:
            raise UserError("O número de páginas por arquivo deve ser maior que zero.")
        for start in range(0, total, every):
            chunk = list(range(start, min(start + every, total)))
            write_part(chunk, f"paginas_{chunk[0] + 1:02d}-{chunk[-1] + 1:02d}")
    else:
        for i in range(total):
            write_part([i], f"pagina_{i + 1:02d}")

    return jsonify(
        ok=True,
        file=deliver(job, base, items),
        note=f"Documento dividido em {len(items)} arquivo(s).",
    )


@app.post("/api/compress")
def api_compress():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    read_pdf(src)
    base = safe_stem(saved[0]["name"])
    level = request.form.get("level", "medium")
    if level not in {"low", "medium", "high"}:
        level = "medium"
    dst = job_dir(job, "up") / "comprimido.pdf"
    gs_compress(src, dst, level)
    note = ""
    if dst.stat().st_size >= src.stat().st_size:
        shutil.copyfile(src, dst)
        note = "O arquivo já estava otimizado; mantivemos o original."
    else:
        saved_bytes = src.stat().st_size - dst.stat().st_size
        note = f"Economia de {saved_bytes / 1024:.0f} KB."
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_comprimido.pdf", dst)]),
        note=note,
    )


@app.post("/api/repair")
def api_repair():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    base = safe_stem(saved[0]["name"])
    dst = job_dir(job, "up") / "reparado.pdf"
    gs_repair(src, dst)
    pages = len(PdfReader(str(dst)).pages)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_reparado.pdf", dst)]),
        note=f"Estrutura reconstruída ({pages} página(s)). Revise o resultado.",
    )


@app.post("/api/pdf2jpg")
def api_pdf2jpg():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    total = len(read_pdf(src).pages)
    base = safe_stem(saved[0]["name"])
    fmt = request.form.get("format", "jpg").lower()
    if fmt not in {"jpg", "png"}:
        fmt = "jpg"
    try:
        dpi = int(request.form.get("dpi", "150"))
    except ValueError:
        dpi = 150
    dpi = max(50, min(dpi, 600))
    work = job_dir(job, "up") / "paginas"
    work.mkdir(exist_ok=True)
    prefix = work / "page"
    ext = "jpeg" if fmt == "jpg" else "png"
    cmd = ["pdftoppm", "-r", str(dpi), f"-{ext}"]
    if fmt == "jpg":
        cmd += ["-jpegopt", "quality=90"]
    cmd += [str(src), str(prefix)]
    run(cmd, timeout=600)
    generated = sorted(work.glob(f"page-*.{'jpg' if fmt == 'jpg' else 'png'}"),
                       key=lambda p: int(re.search(r"(\d+)$", p.stem).group(1)))
    if not generated:
        raise UserError("Nenhuma imagem foi gerada.")
    items = [
        (f"{base}_pagina_{i + 1:02d}.{fmt}", path)
        for i, path in enumerate(generated)
    ]
    return jsonify(
        ok=True,
        file=deliver(job, base, items),
        note=f"{len(items)} de {total} página(s) convertidas em {fmt.upper()}.",
    )


@app.post("/api/img2pdf")
def api_img2pdf():
    job = new_job()
    saved = save_uploads(job, IMAGE_EXTS)
    base = safe_stem(saved[0]["name"])
    layout = request.form.get("layout", "a4")
    pages: list[Image.Image] = []
    for item in saved:
        try:
            with Image.open(item["path"]) as im:
                img = ImageOps.exif_transpose(im).convert("RGB")
        except Exception:
            raise UserError(f'Não foi possível ler a imagem "{item["name"]}".')
        if layout == "a4":
            dpi = 150
            short, long = int(8.27 * dpi), int(11.69 * dpi)
            if img.width > img.height:
                canvas_size = (long, short)
            else:
                canvas_size = (short, long)
            sheet = Image.new("RGB", canvas_size, "white")
            thumb = img.copy()
            thumb.thumbnail((canvas_size[0] - 80, canvas_size[1] - 80), Image.LANCZOS)
            sheet.paste(
                thumb,
                ((canvas_size[0] - thumb.width) // 2,
                 (canvas_size[1] - thumb.height) // 2),
            )
            pages.append(sheet)
        else:
            pages.append(img)
    dst = job_dir(job, "up") / "imagens.pdf"
    if not pages:
        raise UserError("Nenhuma imagem válida enviada.")
    pages[0].save(
        dst, "PDF", save_all=True, append_images=pages[1:], resolution=150.0
    )
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_imagens.pdf", dst)]),
        note=f"{len(pages)} imagem(ns) convertida(s) em PDF.",
    )


@app.post("/api/rotate")
def api_rotate():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    total = len(reader.pages)
    base = safe_stem(saved[0]["name"])
    try:
        angle = int(request.form.get("angle", "90"))
    except ValueError:
        angle = 90
    if angle not in (90, 180, 270):
        raise UserError("Ângulo inválido.")
    spec = request.form.get("pages", "")
    selected = parse_ranges(spec, total, allow_empty=True)
    writer = PdfWriter()
    for idx, page in enumerate(reader.pages):
        if idx in selected:
            page.rotate(angle)
        writer.add_page(page)
    dst = job_dir(job, "up") / "rotacionado.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_rotacionado.pdf", dst)]),
        note=f"{len(selected)} página(s) giradas em {angle}°.",
    )


@app.post("/api/extract")
def api_extract():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    base = safe_stem(saved[0]["name"])
    indices = parse_ranges(request.form.get("pages", ""), len(reader.pages))
    writer = PdfWriter()
    for idx in indices:
        writer.add_page(reader.pages[idx])
    dst = job_dir(job, "up") / "extraido.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_extraido.pdf", dst)]),
        note=f"{len(indices)} página(s) extraídas.",
    )


@app.post("/api/remove")
def api_remove():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    total = len(reader.pages)
    base = safe_stem(saved[0]["name"])
    remove = set(parse_ranges(request.form.get("pages", ""), total))
    keep = [i for i in range(total) if i not in remove]
    if not keep:
        raise UserError("Não é possível remover todas as páginas do documento.")
    writer = PdfWriter()
    for idx in keep:
        writer.add_page(reader.pages[idx])
    dst = job_dir(job, "up") / "sem_paginas.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_sem_paginas.pdf", dst)]),
        note=f"{total - len(keep)} página(s) removidas; restam {len(keep)}.",
    )


@app.post("/api/reorder")
def api_reorder():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    base = safe_stem(saved[0]["name"])
    order = parse_ranges(request.form.get("order", ""), len(reader.pages))
    writer = PdfWriter()
    for idx in order:
        writer.add_page(reader.pages[idx])
    dst = job_dir(job, "up") / "organizado.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_organizado.pdf", dst)]),
        note=f"Nova ordem aplicada a {len(order)} página(s).",
    )


@app.post("/api/crop")
def api_crop():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    base = safe_stem(saved[0]["name"])

    def margin(name: str) -> float:
        try:
            value = float(request.form.get(name, "0"))
        except ValueError:
            raise UserError("Margens inválidas.")
        return max(0.0, min(value, 45.0))

    top, right = margin("top"), margin("right")
    bottom, left = margin("bottom"), margin("left")
    if max(top, right, bottom, left) <= 0:
        raise UserError("Informe ao menos uma margem maior que zero.")

    writer = PdfWriter()
    for page in reader.pages:
        box = page.mediabox
        width, height = float(box.width), float(box.height)
        x0 = float(box.left) + width * left / 100
        x1 = float(box.right) - width * right / 100
        y0 = float(box.bottom) + height * bottom / 100
        y1 = float(box.top) - height * top / 100
        if x1 - x0 < 50 or y1 - y0 < 50:
            raise UserError("O recorte deixaria a página pequena demais.")
        page.cropbox = RectangleObject((x0, y0, x1, y1))
        page.mediabox = RectangleObject((x0, y0, x1, y1))
        writer.add_page(page)

    dst = job_dir(job, "up") / "recortado.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_recortado.pdf", dst)]),
        note=f"Margens aplicadas em {len(writer.pages)} página(s).",
    )


@app.post("/api/watermark")
def api_watermark():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    read_pdf(src)
    base = safe_stem(saved[0]["name"])
    text = (request.form.get("text") or "").strip()
    if not text:
        raise UserError("Digite o texto da marca d'água.")
    try:
        opacity = float(request.form.get("opacity", "0.25"))
    except ValueError:
        opacity = 0.25
    opacity = max(0.05, min(opacity, 1.0))
    try:
        size = float(request.form.get("size", "48"))
    except ValueError:
        size = 48.0
    size = max(8, min(size, 200))
    try:
        rotation = float(request.form.get("rotation", "45"))
    except ValueError:
        rotation = 45.0
    position = request.form.get("position", "center")
    if position not in {
        "center", "top-left", "top-right", "top-center",
        "bottom-left", "bottom-right", "bottom-center",
    }:
        position = "center"
    color = request.form.get("color", "#ff0000")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        color = "#ff0000"
    tiled = request.form.get("tiled") == "1"
    dst = job_dir(job, "up") / "marca_dagua.pdf"
    make_watermark(src, dst, text, opacity, position, size, rotation, color, tiled)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_marca_dagua.pdf", dst)]),
        note="Marca d'água aplicada a todas as páginas.",
    )


@app.post("/api/pagenumbers")
def api_pagenumbers():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    total = len(read_pdf(src).pages)
    base = safe_stem(saved[0]["name"])
    patterns = {
        "simple": "{n} / {total}",
        "page": "Página {n} de {total}",
        "dash": "- {n} -",
    }
    fmt = patterns.get(request.form.get("format", "simple"), "{n} / {total}")
    position = request.form.get("position", "bottom-center")
    if position not in {
        "bottom-center", "bottom-left", "bottom-right",
        "top-center", "top-left", "top-right",
    }:
        position = "bottom-center"
    try:
        size = float(request.form.get("size", "11"))
    except ValueError:
        size = 11.0
    size = max(6, min(size, 72))
    try:
        start = int(request.form.get("start", "1"))
    except ValueError:
        start = 1
    try:
        margin = float(request.form.get("margin", "28"))
    except ValueError:
        margin = 28.0
    color = request.form.get("color", "#444444")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        color = "#444444"
    dst = job_dir(job, "up") / "numerado.pdf"
    add_page_numbers(src, dst, position, fmt, size, start, color, margin)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_numerado.pdf", dst)]),
        note=f"Numeração aplicada em {total} página(s).",
    )


@app.post("/api/protect")
def api_protect():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    base = safe_stem(saved[0]["name"])
    password = request.form.get("password", "")
    if len(password) < 4:
        raise UserError("A senha deve ter ao menos 4 caracteres.")
    confirm = request.form.get("confirm", "")
    if confirm and confirm != password:
        raise UserError("A confirmação da senha não confere.")
    owner = request.form.get("owner", "").strip() or f"{password}-{uuid.uuid4().hex[:8]}"
    permissions = UAP(0)
    if request.form.get("allow_print", "1") == "1":
        permissions |= UAP.PRINT | UAP.PRINT_TO_REPRESENTATION
    if request.form.get("allow_copy", "1") == "1":
        permissions |= UAP.EXTRACT | UAP.EXTRACT_TEXT_AND_GRAPHICS
    if request.form.get("allow_modify", "0") == "1":
        permissions |= UAP.MODIFY | UAP.ADD_OR_MODIFY | UAP.FILL_FORM_FIELDS | UAP.ASSEMBLE_DOC
    writer = PdfWriter()
    for page in reader.pages:
        writer.add_page(page)
    writer.encrypt(
        user_password=password,
        owner_password=owner,
        permissions_flag=permissions,
        algorithm="AES-256",
    )
    dst = job_dir(job, "up") / "protegido.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_protegido.pdf", dst)]),
        note="PDF protegido com senha (AES-256).",
    )


@app.post("/api/unlock")
def api_unlock():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    base = safe_stem(saved[0]["name"])
    password = request.form.get("password", "")
    reader = read_pdf(src, password)
    writer = PdfWriter()
    for page in reader.pages:
        writer.add_page(page)
    dst = job_dir(job, "up") / "desbloqueado.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_desbloqueado.pdf", dst)]),
        note="Proteção removida do documento.",
    )


@app.post("/api/ocr")
def api_ocr():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    reader = read_pdf(src)
    total = len(reader.pages)
    base = safe_stem(saved[0]["name"])
    try:
        dpi = int(request.form.get("dpi", "200"))
    except ValueError:
        dpi = 200
    dpi = max(100, min(dpi, 400))
    lang = re.sub(r"[^a-z+_-]", "", request.form.get("lang", "eng")) or "eng"
    work = job_dir(job, "up") / "ocr"
    work.mkdir(exist_ok=True)
    prefix = work / "page"
    run(["pdftoppm", "-r", str(dpi), "-png", str(src), str(prefix)], timeout=600)
    pages = sorted(work.glob("page-*.png"),
                   key=lambda p: int(re.search(r"(\d+)$", p.stem).group(1)))
    if not pages:
        raise UserError("Nenhuma página foi renderizada para o OCR.")
    pdfs: list[Path] = []
    for idx, image in enumerate(pages):
        out_base = work / f"ocr_{idx + 1:03d}"
        run(["tesseract", str(image), str(out_base), "-l", lang, "--psm", "3", "pdf"],
            timeout=600)
        produced = out_base.with_suffix(".pdf")
        if produced.exists():
            pdfs.append(produced)
    if not pdfs:
        raise UserError("O OCR não gerou resultado.")
    writer = PdfWriter()
    for pdf in pdfs:
        writer.append(str(pdf), import_outline=False)
    dst = job_dir(job, "up") / "ocr.pdf"
    with open(dst, "wb") as fh:
        writer.write(fh)
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}_ocr.pdf", dst)]),
        note=f"OCR aplicado em {len(pdfs)} de {total} página(s) (idioma: {lang}).",
    )


@app.post("/api/pdf2word")
def api_pdf2word():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    read_pdf(src)
    base = safe_stem(saved[0]["name"])
    work = job_dir(job, "up") / "word"
    work.mkdir(exist_ok=True)
    local_src = work / f"{base}.pdf"
    shutil.copyfile(src, local_src)
    converted = convert_office(local_src, work, "docx")
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}.docx", converted)]),
        note="Conversão feita pelo LibreOffice. Layouts complexos podem variar.",
    )


@app.post("/api/office2pdf")
def api_office2pdf():
    job = new_job()
    saved = save_uploads(job, OFFICE_EXTS)
    base = safe_stem(saved[0]["name"])
    work = job_dir(job, "up") / "office"
    work.mkdir(exist_ok=True)
    items: list[tuple[str, Path]] = []
    for idx, item in enumerate(saved):
        local = work / f"{idx:03d}_{safe_stem(item['name'])}{item['ext']}"
        shutil.copyfile(item["path"], local)
        converted = convert_office(local, work, "pdf")
        friendly = f"{safe_stem(item['name'])}.pdf"
        items.append((friendly, converted))
    note = (
        f"{len(items)} arquivo(s) convertido(s) em PDF."
        if len(items) > 1 else "Arquivo convertido em PDF."
    )
    return jsonify(
        ok=True, file=deliver(job, base, items), note=note
    )


@app.post("/api/pdf2txt")
def api_pdf2txt():
    job = new_job()
    saved = save_uploads(job, {".pdf"})
    src = saved[0]["path"]
    read_pdf(src)
    base = safe_stem(saved[0]["name"])
    dst = job_dir(job, "up") / "texto.txt"
    run(["pdftotext", "-layout", "-enc", "UTF-8", str(src), str(dst)], timeout=300)
    if not dst.exists():
        raise UserError("Não foi possível extrair o texto.")
    text = dst.read_text(encoding="utf-8", errors="replace")
    if not text.strip():
        raise UserError(
            "Nenhum texto encontrado. O PDF parece ser digitalizado; "
            "use a ferramenta OCR."
        )
    return jsonify(
        ok=True,
        file=deliver(job, base, [(f"{base}.txt", dst)]),
        note=f"{len(text.splitlines())} linha(s) de texto extraídas.",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Servidor local de ferramentas PDF (PDF2)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()
    cleanup_old(force=True)
    print(f"\n  PDF2 Local rodando em http://{args.host}:{args.port}\n")
    app.run(host=args.host, port=args.port, debug=args.debug, threaded=True)


if __name__ == "__main__":
    main()
