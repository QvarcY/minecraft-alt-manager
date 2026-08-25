(() => {
  const body = document.body;
  const source = body.dataset.source;
  const mode = body.dataset.mode || "guide";
  const lang = body.dataset.lang || "en";
  const mount = document.getElementById("document");
  const toc = document.getElementById("toc-links");

  const esc = (s) => String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");

  const slug = (s) => s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g,"")
    .replace(/[^a-z0-9āčēģīķļņšūž]+/gi,"-")
    .replace(/^-+|-+$/g,"")
    .slice(0,80) || "section";

  function inline(text){
    let out = esc(text);
    out = out.replace(/(https?:\/\/[^\s<]+)/g,'<a href="$1" target="_blank" rel="noopener">$1</a>');
    out = out.replace(/(\{(?:password|username|host|port)\})/g,'<code>$1</code>');
    out = out.replace(/(^|\s)(\/[a-zA-Z][^\s<]*)/g,'$1<code>$2</code>');
    out = out.replace(/(^|\s)((?:RUN|INSTALL|UNINSTALL|SELF-TEST|CLEAN-PORTABLE-DATA|BUILD-USB|SET-VERSION)[A-Z0-9.-]*\.(?:cmd|ps1))/g,'$1<code>$2</code>');
    return out;
  }

  function render(text){
    text = text.replace(/^\uFEFF/,"").replace(/\r\n/g,"\n");
    const lines = text.split("\n");
    let html = "";
    let tocItems = [];
    let i = 0;
    let listType = null;

    const closeList = () => {
      if(listType){ html += `</${listType}>`; listType = null; }
    };

    while(i < lines.length){
      const raw = lines[i];
      const line = raw.trimEnd();
      const trimmed = line.trim();
      const next = i + 1 < lines.length ? lines[i+1].trim() : "";

      if(!trimmed){
        closeList();
        i++;
        continue;
      }

      if(/^={4,}$/.test(next) || /^-{4,}$/.test(next)){
        closeList();
        const level = /^={4,}$/.test(next) ? 1 : 2;
        const id = slug(trimmed);
        if(level === 1){
          html += `<h1 id="${id}">${inline(trimmed)}</h1>`;
        }else{
          html += `<h2 id="${id}">${inline(trimmed)}</h2>`;
          tocItems.push([id, trimmed]);
        }
        i += 2;
        continue;
      }

      if(mode === "changelog" && /^[A-ZĀČĒĢĪĶĻŅŠŪŽ][A-ZĀČĒĢĪĶĻŅŠŪŽ\s/+-]{2,40}$/.test(trimmed) && !/^MINECRAFT/.test(trimmed)){
        closeList();
        const id = slug(trimmed);
        html += `<h3 id="${id}">${inline(trimmed)}</h3>`;
        tocItems.push([id, trimmed]);
        i++;
        continue;
      }

      if(/^- /.test(trimmed)){
        if(listType !== "ul"){ closeList(); listType = "ul"; html += "<ul>"; }
        html += `<li>${inline(trimmed.slice(2))}</li>`;
        i++;
        continue;
      }

      if(/^\d+\.\s+/.test(trimmed)){
        if(listType !== "ol"){ closeList(); listType = "ol"; html += "<ol>"; }
        html += `<li>${inline(trimmed.replace(/^\d+\.\s+/,""))}</li>`;
        i++;
        continue;
      }

      if(/^\s{2,}/.test(raw)){
        closeList();
        html += `<div class="indent">${inline(trimmed)}</div>`;
        i++;
        continue;
      }

      if(
        /^%LOCALAPPDATA%/.test(trimmed) ||
        /^https?:\/\//.test(trimmed) ||
        /^\/[a-zA-Z]/.test(trimmed) ||
        /^(RUN-|INSTALL|UNINSTALL|SELF-TEST|CLEAN-PORTABLE-DATA|BUILD-USB|SET-VERSION)/.test(trimmed) ||
        /^\{(?:password|username|host|port)\}/.test(trimmed)
      ){
        closeList();
        html += `<div class="codeblock">${esc(trimmed)}</div>`;
        i++;
        continue;
      }

      if(/^(Important:|Svarīgi:)/i.test(trimmed)){
        closeList();
        html += `<div class="notice">${inline(trimmed)}</div>`;
        i++;
        continue;
      }

      closeList();
      html += `<p>${inline(trimmed)}</p>`;
      i++;
    }

    closeList();

    mount.innerHTML = html;
    toc.innerHTML = tocItems
      .filter((item,index,self) => self.findIndex(x => x[0] === item[0]) === index)
      .map(([id,label]) => `<a href="#${id}">${esc(label)}</a>`)
      .join("");

    if(!toc.innerHTML){
      toc.innerHTML = `<span style="color:var(--muted);font-size:.7rem">${lang === "lv" ? "Sadaļas tiks parādītas šeit." : "Sections will appear here."}</span>`;
    }
  }

  fetch(source, {cache:"no-cache"})
    .then(r => {
      if(!r.ok) throw new Error(`${r.status} ${r.statusText}`);
      return r.text();
    })
    .then(render)
    .catch(err => {
      mount.innerHTML = `<div class="errorbox">Could not load documentation source: ${esc(err.message)}</div>`;
    });
})();