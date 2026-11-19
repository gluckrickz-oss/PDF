/* Ferramentas PDF Local — interface */
(() => {
  "use strict";

  const ICONS = {
    merge: '<path d="M7 4v5a4 4 0 0 0 4 4h6"/><path d="M17 4v5a4 4 0 0 1-4 4H7"/><path d="M14 10l3 3-3 3"/>',
    split: '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M8.2 8.2L20 20M8.2 15.8L20 4"/>',
    compress: '<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/><path d="M9 9L5 5M15 9l4-4M9 15l-4 4M15 15l4 4"/>',
    pdf2jpg: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="M21 15l-5-5L5 20"/>',
    img2pdf: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 12h8M12 8v8"/>',
    rotate: '<path d="M21 12a9 9 0 1 1-3-6.7"/><path d="M21 3v6h-6"/>',
    extract: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/><path d="M9 15h6"/>',
    remove: '<path d="M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13"/><path d="M10 11v6M14 11v6"/>',
    reorder: '<path d="M4 7h16M4 12h10M4 17h13"/><path d="M18 10l3 2-3 2"/>',
    watermark: '<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"/>',
    pagenumbers: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M8 9h8M8 13h5"/><path d="M15 17h3"/>',
    protect: '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/><circle cx="12" cy="15.5" r="1.5"/>',
    unlock: '<rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 7.5-2"/><circle cx="12" cy="15.5" r="1.5"/>',
    ocr: '<path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3"/><path d="M8 12h8M8 9h8M8 15h5"/>',
    pdf2word: '<path d="M6 2h9l5 5v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z"/><path d="M15 2v5h5"/><path d="M8 13l1.5 5L12 13l1.5 5L16 13"/>',
    office2pdf: '<path d="M6 2h9l5 5v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z"/><path d="M15 2v5h5"/><path d="M8 13h8M8 17h5"/>',
    pdf2txt: '<path d="M6 2h9l5 5v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z"/><path d="M15 2v5h5"/><path d="M8 12h8M8 16h8M8 8h3"/>',
    crop: '<path d="M6 2v14a2 2 0 0 0 2 2h14"/><path d="M2 6h14a2 2 0 0 1 2 2v14"/>',
    repair: '<path d="M14.7 6.3a4 4 0 0 0-5.2 5.2L3 18l3 3 6.5-6.5a4 4 0 0 0 5.2-5.2l-2.5 2.5-2.5-2.5z"/>'
  };

  const PDF = ".pdf,application/pdf";
  const IMGS = ".jpg,.jpeg,.png,.webp,.bmp,.tif,.tiff,image/*";
  const DOCS = ".doc,.docx,.odt,.rtf,.txt,.ppt,.pptx,.odp,.xls,.xlsx,.ods,.csv,.html";

  const TOOLS = [
    { id: "merge", name: "Juntar PDF", desc: "Combine vários PDFs em um único documento.", icon: "merge", color: "c-blue", category: "organizar", accept: PDF, multiple: true, min: 2, hint: "A ordem dos arquivos define a ordem das páginas." },
    { id: "split", name: "Dividir PDF", desc: "Separe páginas em arquivos independentes.", icon: "split", color: "c-orange", category: "organizar", accept: PDF,
      options: [
        { type: "select", id: "mode", label: "Como dividir", value: "each", choices: [["each", "Uma página por arquivo"], ["ranges", "Por intervalos"], ["fixed", "A cada N páginas"]] },
        { type: "text", id: "ranges", label: "Intervalos", placeholder: "1-3, 4-6", when: ["mode", "ranges"], hint: "Cada intervalo gera um PDF." },
        { type: "number", id: "every", label: "Páginas por arquivo", value: 2, min: 1, max: 500, when: ["mode", "fixed"] }
      ] },
    { id: "reorder", name: "Organizar Páginas", desc: "Mude a ordem das páginas do documento.", icon: "reorder", color: "c-cyan", category: "organizar", accept: PDF,
      options: [{ type: "text", id: "order", label: "Nova ordem", placeholder: "3, 1-2, 5, 4", hint: "Use todas as páginas na ordem desejada." }] },
    { id: "extract", name: "Extrair Páginas", desc: "Mantenha apenas as páginas escolhidas.", icon: "extract", color: "c-indigo", category: "organizar", accept: PDF,
      options: [{ type: "text", id: "pages", label: "Páginas", placeholder: "1-3, 5, 8-10", hint: "Você pode repetir páginas." }] },
    { id: "remove", name: "Remover Páginas", desc: "Apague páginas indesejadas do PDF.", icon: "remove", color: "c-red", category: "organizar", accept: PDF,
      options: [{ type: "text", id: "pages", label: "Páginas a remover", placeholder: "2, 4-6" }] },
    { id: "compress", name: "Comprimir PDF", desc: "Reduza o tamanho mantendo a qualidade.", icon: "compress", color: "c-green", category: "otimizar", accept: PDF,
      options: [
        { type: "select", id: "level", label: "Nível de compressão", value: "medium", choices: [["low", "Baixa — melhor qualidade"], ["medium", "Média — recomendada"], ["high", "Alta — menor arquivo"]] }
      ] },
    { id: "repair", name: "Reparar PDF", desc: "Tente recuperar um PDF com danos ou erros.", icon: "repair", color: "c-rose", category: "otimizar", accept: PDF, hint: "Reconstrói a estrutura do arquivo. Revise o resultado." },
    { id: "crop", name: "Recortar PDF", desc: "Reduza as margens e o tamanho das páginas.", icon: "crop", color: "c-emerald", category: "editar", accept: PDF,
      options: [
        { type: "number", id: "top", label: "Margem superior (%)", value: 0, min: 0, max: 95, step: 0.1 },
        { type: "number", id: "right", label: "Margem direita (%)", value: 0, min: 0, max: 95, step: 0.1 },
        { type: "number", id: "bottom", label: "Margem inferior (%)", value: 0, min: 0, max: 95, step: 0.1 },
        { type: "number", id: "left", label: "Margem esquerda (%)", value: 0, min: 0, max: 95, step: 0.1 }
      ], hint: "Selecione a área na prévia ou ajuste os valores." },
    { id: "rotate", name: "Girar PDF", desc: "Corrija páginas de cabeça para baixo.", icon: "rotate", color: "c-teal", category: "editar", accept: PDF,
      options: [
        { type: "select", id: "angle", label: "Rotação", value: "90", choices: [["90", "90° (horário)"], ["180", "180°"], ["270", "270° (anti-horário)"]] },
        { type: "text", id: "pages", label: "Páginas (opcional)", placeholder: "todas — ou 1-3, 5", hint: "Deixe vazio para girar todas." }
      ] },
    { id: "watermark", name: "Marca d'água", desc: "Carimbe um texto em todas as páginas.", icon: "watermark", color: "c-amber", category: "editar", accept: PDF,
      options: [
        { type: "text", id: "text", label: "Texto", placeholder: "CONFIDENCIAL", value: "CONFIDENCIAL" },
        { type: "range", id: "opacity", label: "Opacidade", value: 0.25, min: 0.05, max: 1, step: 0.05 },
        { type: "select", id: "position", label: "Posição", value: "center", choices: [["center", "Centro"], ["bottom-center", "Rodapé central"], ["bottom-right", "Rodapé direito"], ["top-center", "Topo central"], ["top-right", "Topo direito"]] },
        { type: "number", id: "size", label: "Tamanho da fonte", value: 48, min: 8, max: 200 },
        { type: "number", id: "rotation", label: "Rotação (°)", value: 45, min: 0, max: 360 },
        { type: "color", id: "color", label: "Cor", value: "#ff0000" },
        { type: "checkbox", id: "tiled", label: "Repetir em mosaico", value: false }
      ] },
    { id: "pagenumbers", name: "Numerar Páginas", desc: "Adicione números às páginas do PDF.", icon: "pagenumbers", color: "c-slate", category: "editar", accept: PDF,
      options: [
        { type: "select", id: "position", label: "Posição", value: "bottom-center", choices: [["bottom-center", "Rodapé central"], ["bottom-right", "Rodapé direito"], ["bottom-left", "Rodapé esquerdo"], ["top-center", "Topo central"], ["top-right", "Topo direito"], ["top-left", "Topo esquerdo"]] },
        { type: "select", id: "format", label: "Formato", value: "simple", choices: [["simple", "1 / 10"], ["page", "Página 1 de 10"], ["dash", "- 1 -"]] },
        { type: "number", id: "size", label: "Tamanho da fonte", value: 11, min: 6, max: 72 },
        { type: "number", id: "start", label: "Começar em", value: 1, min: 0, max: 100000 },
        { type: "number", id: "margin", label: "Margem (pt)", value: 28, min: 4, max: 200 },
        { type: "color", id: "color", label: "Cor", value: "#444444" }
      ] },
    { id: "pdf2jpg", name: "PDF para Imagem", desc: "Transforme páginas em JPG ou PNG.", icon: "pdf2jpg", color: "c-purple", category: "converter", accept: PDF,
      options: [
        { type: "select", id: "format", label: "Formato", value: "jpg", choices: [["jpg", "JPG"], ["png", "PNG"]] },
        { type: "select", id: "dpi", label: "Resolução", value: "150", choices: [["72", "72 dpi — tela"], ["150", "150 dpi — padrão"], ["300", "300 dpi — impressão"]] }
      ] },
    { id: "img2pdf", name: "Imagem para PDF", desc: "Junte fotos e imagens em um PDF.", icon: "img2pdf", color: "c-pink", category: "converter", accept: IMGS, multiple: true, min: 1, hint: "A ordem das imagens define a ordem das páginas." },
    { id: "ocr", name: "OCR PDF", desc: "Torne PDFs digitalizados pesquisáveis.", icon: "ocr", color: "c-violet", category: "converter", accept: PDF,
      options: [
        { type: "select", id: "lang", label: "Idioma do documento", value: "eng", choices: [] },
        { type: "select", id: "dpi", label: "Qualidade", value: "200", choices: [["150", "Rápido"], ["200", "Equilibrado"], ["300", "Preciso (mais lento)"]] }
      ] },
    { id: "pdf2word", name: "PDF para Word", desc: "Converta o PDF em um arquivo DOCX.", icon: "pdf2word", color: "c-blue", category: "converter", accept: PDF, hint: "Layouts muito complexos podem sofrer ajustes." },
    { id: "office2pdf", name: "Office para PDF", desc: "Word, Excel, PowerPoint e mais em PDF.", icon: "office2pdf", color: "c-orange", category: "converter", accept: DOCS, multiple: true, min: 1, hint: "Formatos: DOC/DOCX, ODT, RTF, PPT/PPTX, XLS/XLSX, ODS, CSV, HTML." },
    { id: "pdf2txt", name: "PDF para Texto", desc: "Extraia todo o texto em um arquivo TXT.", icon: "pdf2txt", color: "c-gray", category: "converter", accept: PDF },
    { id: "protect", name: "Proteger PDF", desc: "Adicione senha e permissões.", icon: "protect", color: "c-navy", category: "seguranca", accept: PDF,
      options: [
        { type: "password", id: "password", label: "Senha de abertura", placeholder: "mínimo 4 caracteres" },
        { type: "password", id: "confirm", label: "Confirmar senha", placeholder: "repita a senha" },
        { type: "checkbox", id: "allow_print", label: "Permitir impressão", value: true },
        { type: "checkbox", id: "allow_copy", label: "Permitir cópia de texto", value: true },
        { type: "checkbox", id: "allow_modify", label: "Permitir modificação", value: false }
      ] },
    { id: "unlock", name: "Desbloquear PDF", desc: "Remova a senha de abertura do PDF.", icon: "unlock", color: "c-lime", category: "seguranca", accept: PDF,
      options: [{ type: "password", id: "password", label: "Senha atual", placeholder: "deixe vazio se não houver" }] }
  ];

  const CATEGORIES = [
    ["all", "Todas"],
    ["organizar", "Organizar"],
    ["otimizar", "Otimizar"],
    ["editar", "Editar"],
    ["converter", "Converter"],
    ["seguranca", "Segurança"]
  ];
  const CATEGORY_LABEL = Object.fromEntries(CATEGORIES);
  const STEPS = ["Arquivo", "Configurar", "Baixar"];

  const state = { tool: null, files: [], busy: false, objectUrl: null };

  const grid = document.getElementById("grid");
  const modal = document.getElementById("modal");
  const body = document.getElementById("modal-body");
  const langs = (document.getElementById("langs")?.dataset.langs || "eng").split(",");

  function h(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(attrs)) {
      if (value === null || value === undefined || value === false) continue;
      if (key === "class") node.className = value;
      else if (key === "html") node.innerHTML = value;
      else if (key.startsWith("on") && typeof value === "function") {
        node.addEventListener(key.slice(2), value);
      } else if (key === "value" || key === "checked") node[key] = value;
      else node.setAttribute(key, value === true ? "" : value);
    }
    for (const child of children.flat()) {
      if (child === null || child === undefined || child === false) continue;
      node.append(child.nodeType ? child : document.createTextNode(String(child)));
    }
    return node;
  }

  function icon(name, size = 26) {
    return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ICONS.pdf2txt}</svg>`;
  }

  function formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  function matchesAccept(file, accept) {
    if (!accept) return true;
    const types = accept.split(",").map((s) => s.trim().toLowerCase());
    const name = file.name.toLowerCase();
    return types.some((t) => {
      if (t.startsWith(".")) return name.endsWith(t);
      if (t.endsWith("/*")) return file.type.toLowerCase().startsWith(t.slice(0, -1));
      return file.type.toLowerCase() === t;
    });
  }

  let activeCategory = "all";

  function stepsBar(active = 1) {
    return h("ol", { class: "steps" }, STEPS.map((label, index) => {
      const n = index + 1;
      const cls = n === active ? "step active" : n < active ? "step done" : "step";
      return h("li", { class: cls },
        h("span", { class: "step-num" }, n < active ? "✓" : String(n)),
        h("span", {}, label)
      );
    }));
  }

  function setStep(active) {
    if (!current || !current.steps) return;
    const fresh = stepsBar(active);
    current.steps.replaceWith(fresh);
    current.steps = fresh;
  }

  function renderFilters() {
    const wrap = document.getElementById("filters");
    if (!wrap) return;
    wrap.innerHTML = "";
    for (const [id, label] of CATEGORIES) {
      const count = id === "all" ? TOOLS.length : TOOLS.filter((t) => t.category === id).length;
      wrap.append(h("button", {
        type: "button",
        class: "chip" + (id === activeCategory ? " active" : ""),
        "aria-pressed": id === activeCategory ? "true" : "false",
        onclick: () => { activeCategory = id; renderFilters(); renderGrid(); }
      }, label, h("span", { class: "chip-count" }, String(count))));
    }
  }

  function renderGrid() {
    grid.innerHTML = "";
    const visible = TOOLS.filter((t) => activeCategory === "all" || t.category === activeCategory);
    for (const tool of visible) {
      const card = h("button", { class: "tool-card", type: "button", "data-category": tool.category, onclick: () => openTool(tool) },
        h("span", { class: `tool-icon ${tool.color}`, html: icon(tool.icon) }),
        h("span", { class: "tool-text" },
          h("strong", {}, tool.name),
          h("span", {}, tool.desc),
          h("span", { class: "tool-cat" }, CATEGORY_LABEL[tool.category])
        )
      );
      grid.append(card);
    }
  }

  function renderFiles(listEl, tool) {
    listEl.innerHTML = "";
    if (!state.files.length) {
      listEl.classList.add("hidden");
      return;
    }
    listEl.classList.remove("hidden");
    state.files.forEach((file, index) => {
      const controls = h("span", { class: "file-controls" });
      if (tool.multiple && state.files.length > 1) {
        controls.append(
          h("button", { type: "button", class: "icon-btn", title: "Mover para cima", disabled: index === 0, onclick: () => moveFile(index, -1), html: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg>' }),
          h("button", { type: "button", class: "icon-btn", title: "Mover para baixo", disabled: index === state.files.length - 1, onclick: () => moveFile(index, 1), html: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>' })
        );
      }
      controls.append(
        h("button", { type: "button", class: "icon-btn danger", title: "Remover", onclick: () => removeFile(index), html: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>' })
      );
      listEl.append(
        h("div", { class: "file-row" },
          h("span", { class: "file-type" }, (file.name.split(".").pop() || "").toUpperCase().slice(0, 5)),
          h("span", { class: "file-name", title: file.name }, file.name),
          h("span", { class: "file-size" }, formatSize(file.size)),
          controls
        )
      );
    });
  }

  function moveFile(index, delta) {
    const target = index + delta;
    if (target < 0 || target >= state.files.length) return;
    [state.files[index], state.files[target]] = [state.files[target], state.files[index]];
    refreshFiles();
  }

  function removeFile(index) {
    state.files.splice(index, 1);
    refreshFiles();
  }

  let current = null;

  function refreshFiles() {
    if (!current) return;
    renderFiles(current.listEl, current.tool);
    updateSubmitState();
    if (current.tool.id === "crop") refreshCropPreview();
    setStep(state.files.length ? 2 : 1);
  }

  function updateSubmitState() {
    if (!current) return;
    const btn = current.submit;
    const min = current.tool.min || 1;
    const enough = state.files.length >= min;
    btn.disabled = state.busy || !enough;
  }

  const CROP_MIN = 0.05;

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function fileKey(file) {
    return `${file.name}:${file.size}:${file.lastModified || 0}`;
  }

  function buildCropPreview() {
    const image = h("img", { class: "crop-image", alt: "Prévia da página do PDF" });
    const box = h("div", { class: "crop-box hidden" });
    for (const name of ["nw", "n", "ne", "e", "se", "s", "sw", "w"]) {
      box.append(h("span", { class: "crop-handle", "data-handle": name }));
    }
    const canvas = h("div", { class: "crop-canvas" }, image, box);
    const stage = h("div", { class: "crop-stage" }, canvas);
    const label = h("span", { class: "crop-page-label" }, "Página 1");
    const prev = h("button", { type: "button", class: "icon-btn", title: "Página anterior", disabled: true }, "‹");
    const next = h("button", { type: "button", class: "icon-btn", title: "Próxima página", disabled: true }, "›");
    const status = h("div", { class: "crop-status" }, "Selecione um PDF para visualizar.");
    const el = h("div", { class: "crop-preview hidden" },
      h("div", { class: "crop-preview-head" },
        h("span", { class: "crop-preview-title" }, "Ajuste visual do recorte"),
        h("div", { class: "crop-pager" }, prev, label, next)
      ),
      stage,
      status,
      h("small", { class: "hint" }, "Arraste a área ou os cantos. O recorte será aplicado a todas as páginas.")
    );
    return {
      el, image, box, canvas, label, prev, next, status,
      job: null, page: 1, pages: 0, sourceKey: null,
      rect: { l: 0, t: 0, r: 1, b: 1 }, loaded: false, controller: null
    };
  }

  function constrainCrop(rect) {
    let l = clamp(rect.l, 0, 1);
    let r = clamp(rect.r, 0, 1);
    let t = clamp(rect.t, 0, 1);
    let b = clamp(rect.b, 0, 1);
    if (r - l < CROP_MIN) {
      if (l + CROP_MIN <= 1) r = l + CROP_MIN;
      else {
        r = 1;
        l = 1 - CROP_MIN;
      }
    }
    if (b - t < CROP_MIN) {
      if (t + CROP_MIN <= 1) b = t + CROP_MIN;
      else {
        b = 1;
        t = 1 - CROP_MIN;
      }
    }
    return { l, r, t, b };
  }

  function optionNumber(id) {
    if (!current) return 0;
    const input = current.form.querySelector(`[data-opt="${id}"]`);
    const value = input ? parseFloat(input.value) : 0;
    return Number.isFinite(value) ? value : 0;
  }

  function rectFromInputs() {
    return constrainCrop({
      l: clamp(optionNumber("left"), 0, 95) / 100,
      r: 1 - clamp(optionNumber("right"), 0, 95) / 100,
      t: clamp(optionNumber("top"), 0, 95) / 100,
      b: 1 - clamp(optionNumber("bottom"), 0, 95) / 100
    });
  }

  function syncCropInputs(rect) {
    if (!current) return;
    const values = {
      top: rect.t * 100,
      right: (1 - rect.r) * 100,
      bottom: (1 - rect.b) * 100,
      left: rect.l * 100
    };
    for (const [id, value] of Object.entries(values)) {
      const input = current.form.querySelector(`[data-opt="${id}"]`);
      if (input) input.value = String(Math.round(value * 10) / 10);
    }
  }

  function updateCropStatus(rect) {
    const cp = current && current.crop;
    if (!cp) return;
    const w = ((rect.r - rect.l) * 100).toFixed(1);
    const h = ((rect.b - rect.t) * 100).toFixed(1);
    cp.status.textContent = `Área selecionada: ${w}% × ${h}% da página.`;
  }

  function setCropRect(rect, syncInputs = true) {
    const cp = current && current.crop;
    if (!cp) return;
    const next = constrainCrop(rect);
    cp.rect = next;
    cp.box.style.left = `${next.l * 100}%`;
    cp.box.style.top = `${next.t * 100}%`;
    cp.box.style.width = `${(next.r - next.l) * 100}%`;
    cp.box.style.height = `${(next.b - next.t) * 100}%`;
    cp.box.classList.remove("hidden");
    if (syncInputs) syncCropInputs(next);
    updateCropStatus(next);
  }

  function syncCropFromInputs() {
    const cp = current && current.crop;
    if (!cp) return;
    const rect = rectFromInputs();
    if (!cp.loaded) {
      cp.rect = rect;
      return;
    }
    setCropRect(rect, false);
  }

  const cropUrl = (data) => data.image_url;

  async function loadCropPreview(file, page) {
    const cp = current && current.crop;
    if (!cp || !file) return;
    if (cp.controller) cp.controller.abort();
    const controller = new AbortController();
    cp.controller = controller;
    cp.el.classList.remove("hidden");
    cp.el.classList.add("loading");
    cp.status.textContent = "Gerando prévia da página...";

    const formData = new FormData();
    if (cp.job) {
      formData.append("job", cp.job);
      formData.append("page", String(page));
    } else {
      formData.append("files", file, file.name);
      formData.append("page", "1");
    }

    try {
      const response = await fetch("/api/crop/preview", {
        method: "POST", body: formData, signal: controller.signal
      });
      let data = null;
      try { data = await response.json(); } catch (_) { /* ignore */ }
      if (current && current.crop !== cp) return;
      if (!response.ok || !data || !data.ok) {
        throw new Error((data && data.error) || `Falha ao gerar prévia (HTTP ${response.status}).`);
      }
      cp.job = data.job;
      cp.page = data.page;
      cp.pages = data.pages;
      cp.label.textContent = `Página ${data.page} de ${data.pages}`;
      cp.prev.disabled = data.page <= 1;
      cp.next.disabled = data.page >= data.pages;
      cp.status.textContent = "Carregando imagem...";
      cp.image.onload = () => {
        if (!current || current.crop !== cp) return;
        cp.loaded = true;
        cp.el.classList.remove("loading");
        setCropRect(cp.rect, false);
        updateCropStatus(cp.rect);
      };
      cp.image.onerror = () => {
        if (!current || current.crop !== cp) return;
        cp.loaded = false;
        cp.el.classList.remove("loading");
        cp.status.textContent = "Não foi possível carregar a imagem da prévia.";
      };
      cp.image.src = cropUrl(data);
      if (cp.image.complete && cp.image.naturalWidth) cp.image.onload();
    } catch (err) {
      if (err.name === "AbortError") return;
      if (!current || current.crop !== cp) return;
      cp.loaded = false;
      cp.el.classList.remove("loading");
      cp.box.classList.add("hidden");
      cp.status.textContent = err.message || "Não foi possível gerar a prévia.";
    } finally {
      if (cp.controller === controller) cp.controller = null;
    }
  }

  function refreshCropPreview() {
    const cp = current && current.crop;
    if (!cp) return;
    if (!state.files.length) {
      if (cp.controller) cp.controller.abort();
      cp.el.classList.add("hidden");
      cp.box.classList.add("hidden");
      cp.job = null;
      cp.sourceKey = null;
      cp.loaded = false;
      return;
    }
    const file = state.files[0];
    const key = fileKey(file);
    if (cp.sourceKey === key) return;
    cp.sourceKey = key;
    cp.job = null;
    cp.page = 1;
    cp.pages = 0;
    cp.rect = rectFromInputs();
    loadCropPreview(file, 1);
  }

  function bindCropPreview(cp) {
    cp.prev.addEventListener("click", () => {
      if (cp.page > 1 && state.files.length) loadCropPreview(state.files[0], cp.page - 1);
    });
    cp.next.addEventListener("click", () => {
      if (cp.page < cp.pages && state.files.length) loadCropPreview(state.files[0], cp.page + 1);
    });

    let drag = null;
    cp.canvas.addEventListener("pointerdown", (event) => {
      const handle = event.target.closest && event.target.closest("[data-handle]");
      const inside = event.target.closest && event.target.closest(".crop-box");
      if (!inside) return;
      const bounds = cp.canvas.getBoundingClientRect();
      if (!bounds.width || !bounds.height) return;
      event.preventDefault();
      if (cp.canvas.setPointerCapture) cp.canvas.setPointerCapture(event.pointerId);
      drag = {
        pointerId: event.pointerId,
        mode: handle ? "resize" : "move",
        handle: handle ? handle.dataset.handle : null,
        startX: event.clientX,
        startY: event.clientY,
        width: bounds.width,
        height: bounds.height,
        rect: { ...cp.rect }
      };
    });

    cp.canvas.addEventListener("pointermove", (event) => {
      if (!drag || event.pointerId !== drag.pointerId) return;
      const dx = (event.clientX - drag.startX) / drag.width;
      const dy = (event.clientY - drag.startY) / drag.height;
      let rect = { ...drag.rect };
      if (drag.mode === "move") {
        const w = rect.r - rect.l;
        const hgt = rect.b - rect.t;
        const left = clamp(rect.l + dx, 0, 1 - w);
        const top = clamp(rect.t + dy, 0, 1 - hgt);
        rect = { l: left, r: left + w, t: top, b: top + hgt };
      } else {
        const handle = drag.handle || "";
        if (handle.includes("w")) rect.l = clamp(rect.l + dx, 0, rect.r - CROP_MIN);
        if (handle.includes("e")) rect.r = clamp(rect.r + dx, rect.l + CROP_MIN, 1);
        if (handle.includes("n")) rect.t = clamp(rect.t + dy, 0, rect.b - CROP_MIN);
        if (handle.includes("s")) rect.b = clamp(rect.b + dy, rect.t + CROP_MIN, 1);
      }
      setCropRect(rect);
    });

    const finish = (event) => {
      if (drag && event.pointerId === drag.pointerId) drag = null;
    };
    cp.canvas.addEventListener("pointerup", finish);
    cp.canvas.addEventListener("pointercancel", finish);
  }

  function openTool(tool) {
    closeModal(true);
    state.tool = tool;
    state.files = [];
    state.busy = false;
    modal.classList.remove("hidden");
    document.body.classList.add("locked");
    body.innerHTML = "";

    const head = h("div", { class: "tool-head" },
      h("div", { class: `tool-icon big ${tool.color}`, html: icon(tool.icon, 30) }),
      h("div", {},
        h("h2", { id: "modal-title" }, tool.name),
        h("p", {}, tool.desc)
      )
    );

    const fileInput = h("input", { type: "file", accept: tool.accept, multiple: tool.multiple, hidden: true });
    fileInput.addEventListener("change", () => {
      addFiles(fileInput.files);
      fileInput.value = "";
    });

    const drop = h("div", { class: "dropzone", role: "button", tabindex: "0" },
      h("span", { class: "drop-icon", html: icon("img2pdf", 30) }),
      h("strong", {}, "Arraste seu arquivo aqui"),
      h("span", { class: "muted" }, tool.multiple ? "ou clique para selecionar vários" : "ou clique para selecionar"),
      tool.hint ? h("small", { class: "hint" }, tool.hint) : null
    );
    drop.addEventListener("click", () => fileInput.click());
    drop.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); fileInput.click(); }
    });
    drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.classList.add("over"); });
    drop.addEventListener("dragleave", () => drop.classList.remove("over"));
    drop.addEventListener("drop", (e) => {
      e.preventDefault();
      drop.classList.remove("over");
      addFiles(e.dataTransfer.files);
    });

    const listEl = h("div", { class: "file-list hidden" });
    const cropPreview = tool.id === "crop" ? buildCropPreview() : null;
    const optionsEl = h("div", { class: "options" });

    if (tool.options) {
      for (const opt of tool.options) optionsEl.append(buildOption(opt));
      const onOptionChange = () => {
        updateVisibility();
        if (tool.id === "crop") syncCropFromInputs();
      };
      optionsEl.addEventListener("change", onOptionChange);
      optionsEl.addEventListener("input", onOptionChange);
      if (tool.id === "ocr") {
        const sel = optionsEl.querySelector('[data-opt="lang"]');
        sel.innerHTML = "";
        for (const lang of langs) {
          sel.append(h("option", { value: lang }, langLabel(lang)));
        }
        sel.value = langs.includes("por") ? "por" : langs[0];
      }
    }

    const error = h("div", { class: "error hidden" });
    const progressText = h("span", { class: "progress-label" }, "0%");
    const bar = h("div", { class: "progress-bar" });
    const progress = h("div", { class: "progress hidden" }, h("div", { class: "progress-track" }, bar), progressText);

    const submit = h("button", { type: "submit", class: "btn primary", disabled: true }, "Processar arquivo");
    const form = h("form", { class: "tool-form", novalidate: true },
      fileInput, drop, listEl, cropPreview ? cropPreview.el : null, optionsEl, error, progress,
      h("div", { class: "actions" }, submit)
    );

    form.addEventListener("submit", (e) => {
      e.preventDefault();
      if (state.busy) return;
      submitForm(tool, form, error, progress, bar, progressText);
    });

    const stepbar = stepsBar(1);
    body.append(head, stepbar, form);
    current = { tool, form, listEl, submit, error, progress, bar, progressText, xhr: null, steps: stepbar, crop: cropPreview };
    if (cropPreview) bindCropPreview(cropPreview);
    updateVisibility();
    updateSubmitState();
    modal.scrollTop = 0;
    drop.focus();
  }

  function langLabel(code) {
    return code === "por" ? "Português" : code === "eng" ? "Inglês" : code === "spa" ? "Espanhol" : code;
  }

  function addFiles(fileList) {
    if (!current) return;
    const tool = current.tool;
    const incoming = Array.from(fileList || []);
    const rejected = incoming.filter((f) => !matchesAccept(f, tool.accept));
    if (rejected.length) {
      showError(current.error, `Formato não aceito: ${rejected[0].name}`);
    } else {
      hideError(current.error);
    }
    const accepted = incoming.filter((f) => matchesAccept(f, tool.accept));
    if (!accepted.length) return;
    if (tool.multiple) state.files = state.files.concat(accepted);
    else state.files = accepted.slice(-1);
    refreshFiles();
  }

  function buildOption(opt) {
    const wrapper = h("div", { class: "option" });
    if (opt.when) wrapper.dataset.when = `${opt.when[0]}:${opt.when[1]}`;
    const labelText = h("span", { class: "option-label" }, opt.label);

    if (opt.type === "checkbox") {
      const input = h("input", { type: "checkbox", "data-opt": opt.id, checked: Boolean(opt.value) });
      const label = h("label", { class: "check" }, input, h("span", {}, opt.label));
      wrapper.append(label);
      return wrapper;
    }

    let input;
    if (opt.type === "select") {
      input = h("select", { "data-opt": opt.id });
      for (const [value, text] of opt.choices) {
        input.append(h("option", { value }, text));
      }
      input.value = String(opt.value);
    } else if (opt.type === "range") {
      input = h("input", { type: "range", "data-opt": opt.id, min: opt.min, max: opt.max, step: opt.step, value: opt.value });
      const out = h("output", {}, String(opt.value));
      input.addEventListener("input", () => { out.textContent = input.value; });
      wrapper.append(labelText, h("div", { class: "range-row" }, input, out));
      if (opt.hint) wrapper.append(h("small", { class: "hint" }, opt.hint));
      return wrapper;
    } else {
      const type = opt.type === "text" ? "text" : opt.type;
      input = h("input", {
        type,
        "data-opt": opt.id,
        value: opt.value ?? "",
        placeholder: opt.placeholder || "",
        min: opt.min,
        max: opt.max,
        autocomplete: opt.type === "password" ? "new-password" : "off"
      });
    }

    wrapper.append(labelText, input);
    if (opt.hint) wrapper.append(h("small", { class: "hint" }, opt.hint));
    return wrapper;
  }

  function updateVisibility() {
    if (!current) return;
    for (const field of current.form.querySelectorAll("[data-when]")) {
      const [id, value] = field.dataset.when.split(":");
      const control = current.form.querySelector(`[data-opt="${id}"]`);
      const visible = control && control.value === value;
      field.classList.toggle("hidden", !visible);
    }
  }

  function showError(el, message) {
    el.textContent = message;
    el.classList.remove("hidden");
  }

  function hideError(el) {
    el.textContent = "";
    el.classList.add("hidden");
  }

  function submitForm(tool, form, error, progress, bar, progressText) {
    hideError(error);
    setStep(2);
    const min = tool.min || 1;
    if (state.files.length < min) {
      showError(error, min > 1 ? `Selecione ao menos ${min} arquivos.` : "Selecione um arquivo.");
      return;
    }
    for (const opt of tool.options || []) {
      if (opt.required) {
        const input = form.querySelector(`[data-opt="${opt.id}"]`);
        if (input && !input.value.trim()) {
          showError(error, `Preencha o campo “${opt.label}”.`);
          input.focus();
          return;
        }
      }
    }

    const formData = new FormData();
    const cropJob = tool.id === "crop" && current.crop && current.crop.job
      && current.crop.sourceKey === fileKey(state.files[0]);
    if (cropJob) {
      formData.append("job", current.crop.job);
    } else {
      for (const file of state.files) formData.append("files", file, file.name);
    }
    for (const opt of tool.options || []) {
      const el = form.querySelector(`[data-opt="${opt.id}"]`);
      if (!el) continue;
      formData.append(opt.id, opt.type === "checkbox" ? (el.checked ? "1" : "0") : el.value);
    }

    const ctx = current;
    state.busy = true;
    ctx.submit.disabled = true;
    ctx.submit.textContent = "Processando...";
    progress.classList.remove("hidden");
    bar.style.width = "0%";
    progressText.textContent = "Enviando...";

    const xhr = new XMLHttpRequest();
    xhr.open("POST", `/api/${tool.id}`);
    xhr.responseType = "text";

    xhr.upload.addEventListener("progress", (e) => {
      if (!e.lengthComputable) return;
      const pct = Math.min(99, Math.round((e.loaded / e.total) * 100));
      bar.style.width = pct + "%";
      progressText.textContent = pct + "%";
    });

    ctx.xhr = xhr;
    xhr.addEventListener("load", () => {
      if (current !== ctx) return;
      ctx.xhr = null;
      state.busy = false;
      ctx.submit.textContent = "Processar arquivo";
      updateSubmitState();
      let data = null;
      try { data = JSON.parse(xhr.responseText); } catch (_) { /* ignore */ }
      if (xhr.status >= 200 && xhr.status < 300 && data && data.ok) {
        bar.style.width = "100%";
        progressText.textContent = "Concluído";
        showResult(tool, data);
      } else {
        progress.classList.add("hidden");
        showError(error, (data && data.error) || `Falha no processamento (HTTP ${xhr.status}).`);
      }
    });

    xhr.addEventListener("error", () => {
      if (current !== ctx) return;
      ctx.xhr = null;
      state.busy = false;
      ctx.submit.textContent = "Processar arquivo";
      updateSubmitState();
      progress.classList.add("hidden");
      showError(error, "Não foi possível conectar ao serviço local.");
    });

    xhr.send(formData);
  }

  function showResult(tool, data) {
    modal.scrollTop = 0;
    body.innerHTML = "";
    const file = data.file;
    const download = h("a", {
      class: "btn primary",
      href: file.url,
      download: file.name
    }, "Baixar arquivo");

    body.append(
      h("div", { class: "tool-head" },
        h("div", { class: `tool-icon big ${tool.color}`, html: icon(tool.icon, 30) }),
        h("div", {},
          h("h2", { id: "modal-title" }, "Pronto!"),
          h("p", {}, tool.name)
        )
      ),
      stepsBar(3),
      h("div", { class: "result" },
        h("div", { class: "result-check", html: '<svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6L9 17l-5-5"/></svg>' }),
        h("div", { class: "file-pill" },
          h("span", { class: "file-name", title: file.name }, file.name),
          h("span", { class: "file-size" }, formatSize(file.size))
        ),
        data.note ? h("p", { class: "note" }, data.note) : null,
        h("div", { class: "actions center" },
          download,
          h("button", { type: "button", class: "btn ghost", onclick: () => openTool(tool) }, "Processar outro arquivo")
        )
      )
    );
  }

  function closeModal(silent = false) {
    if (!silent && state.busy) {
      const ok = window.confirm("O processamento está em andamento. Fechar mesmo assim?");
      if (!ok) return;
    }
    if (current && current.xhr) {
      try { current.xhr.abort(); } catch (_) { /* ignore */ }
    }
    if (current && current.crop && current.crop.controller) {
      try { current.crop.controller.abort(); } catch (_) { /* ignore */ }
    }
    modal.classList.add("hidden");
    document.body.classList.remove("locked");
    state.busy = false;
    state.files = [];
    current = null;
    body.innerHTML = "";
  }

  document.getElementById("modal-close").addEventListener("click", () => closeModal());
  modal.addEventListener("click", (e) => { if (e.target === modal) closeModal(); });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !modal.classList.contains("hidden")) closeModal();
  });

  window.addEventListener("dragover", (e) => e.preventDefault());
  window.addEventListener("drop", (e) => {
    if (!modal.classList.contains("hidden")) return;
    e.preventDefault();
  });

  renderFilters();
  renderGrid();
})();
