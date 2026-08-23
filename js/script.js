/* =========================================================
   R ♥ S — Our Story
   ========================================================= */
(function () {
  'use strict';

  /* =======================================================
     1. DATA  —  عدل من هنا
     ======================================================= */

  const loveStory = {
    raouf: "رؤوف",
    sara: "سارة",
    firstConfession: "2026-08-19"
  };

  /* صورنا الاثنين فقط */
  const portraits = {
    sara:  "assets/images/memories/sara-01.jpg",
    raouf: "assets/images/memories/raouf-01.jpg"
  };

  /* الذكريات — مكتوبة مو صور
     كل ذكرى نص  تقدر تعدلها او تزيد وحدة جديدة بنفس الشكل
     kind يغير شكل البطاقة  note / line / big / quiet */
  const memories = [
    { no:"01", kind:"line",  title:"القروب",
      text:"دخلتي القروب وما كان في شيء كبير وقتها. بس وحدة جديدة دخلت. وانا ما كنت اعرف ان هذا اليوم بيفرق معي." },

    { no:"02", kind:"note",  title:"اول مرة انتبهت",
      text:"ما اذكر اول رسالة كتبتيها بالضبط. بس اذكر اني بديت اقرا كلامك اكثر من كلام غيرك." },

    { no:"03", kind:"quiet", title:"بيني وبين نفسي",
      text:"صرت اذا فتحت القروب ادور اسمك اول شيء." },

    { no:"04", kind:"big",   title:"اي سبب",
      text:"كنت اجيب اي موضوع. اي شيء. المهم تردين علي." },

    { no:"05", kind:"note",  title:"الانتظار",
      text:"اذا تاخرتي في الرد كنت افتح الجوال بدون سبب. اشوف اذا كتبتي شيء." },

    { no:"06", kind:"line",  title:"اللعب",
      text:"صرنا نلعب مع بعض. وانا ما كنت العب عشان اللعبة. كنت العب عشان انتي موجودة." },

    { no:"07", kind:"quiet", title:"صوتك",
      text:"في وقت صار وجودك عادة. واذا ما كنتي موجودة يوم كان اليوم ناقص." },

    { no:"08", kind:"note",  title:"تفاصيلك",
      text:"طريقة كلامك. الكلمات اللي تكررينها. وقت ما تضحكين. كلها صارت اشياء اعرفها عنك." },

    { no:"09", kind:"big",   title:"عرفت",
      text:"ما في لحظة وحدة قلت فيها خلاص انا احبها. صار الموضوع شوي شوي لين صار واضح." },

    { no:"10", kind:"line",  date:"19.08.2026", title:"قلت لك",
      text:"تعبت وانا ساكت. قررت اقول لك كل شيء. وهذا احسن قرار اخذته." }
  ];

  /* المحادثات — ضع الصور في assets/images/conversations/
     تظهر في المعرض فقط  (الصور الاصلية محفوظة كما هي) */
  const conversations = [
    { image: "assets/images/conversations/conversation-01.jpg", caption: "conversation — 01" },
    { image: "assets/images/conversations/conversation-02.jpg", caption: "conversation — 02" },
    { image: "assets/images/conversations/conversation-03.jpg", caption: "conversation — 03" },
    { image: "assets/images/conversations/conversation-04.jpg", caption: "conversation — 04" },  
    { image: "assets/images/conversations/conversation-05.jpg", caption: "conversation — 05" },  
    { image: "assets/images/conversations/conversation-06.jpg", caption: "conversation — 06" },    
    { image: "assets/images/conversations/conversation-07.jpg", caption: "conversation — 07" },
    { image: "assets/images/conversations/conversation-08.jpg", caption: "conversation — 08" },
    { image: "assets/images/conversations/conversation-09.jpg", caption: "conversation — 09" },
    { image: "assets/images/conversations/conversation-10.jpg", caption: "conversation — 10" }

  ];

  /* نص المحادثة الحقيقي — منقول حرف بحرف من المحادثة
     ما تغير فيه شيء  لا كلمة ولا حرف ولا ايموجي
     out = رؤوف     in = سارة     reply = تم الرد عليك */
  const chatThread = [
    { who:"out", text:"شواريك يهبلو 😍🤭😁 والله العظيم غي من قدام يعجبوني 💖🙃🥲" },
    { who:"reply", text:"تم الرد عليك" },
    { who:"in",  text:"مم انا نمممووووت عليك انا حابة نعنقققققققققققك بزاف بزاف وندخل فيك" },
    { who:"in",  text:"والله كي نعنقك حاب نزيرك عندي باقصى قوتي هههههه 😘😘🔥🔥🔥😍😍😍 😍😍😍😍🥰" },
    { who:"reply", text:"تم الرد عليك" },
    { who:"out", text:"شواريك يهبلو 😍🤭😁 والله العظيم غي من قدام يعجبوني 💖🙃🥲" },
    { who:"in",  text:"😍😍😍😍😍😍😍😍😍😍🥰 يعمممممممممرببببي حشمتيييييييني يحبي" },
    { who:"in",  text:"شواريك نتي قتالين يحبي والله ذوبوني 😘🔥🔥🔥🔥🔥🔥🔥🙃🙃🙃 😍😍😍😍🥰🥰🥰😝😘😘" }
  ];
  const chatMeta = { time:"12:51", label:"من محادثتنا" };

  /* الاغاني */
  const playlist = [
    { src:"assets/music/our-song.mp3", name:"اغنيتنا" },
    { src:"assets/music/song-02.mp3",  name:"اغنية ثانية" }
  ];

  /* رسالة الحب — عدل النص بحرية */
  const loveLetter = [
    { text: "سارة" , big: false },
    { text: "يمكن هذا الموقع مجرد صفحة على الانترنت" },
    { text: "لكن بالنسبة لي هو طريقة صغيرة اخلي فيها جزء من قصتنا قدامك" },
    { text: "من يوم دخلتي القروب وانا ما كنت اعرف وش بيصير" },
    { text: "ما كنت اعرف اني ببدا ادور اي سبب عشان اتكلم معك" },
    { text: "ولا كنت اعرف ان رسائلك بتصير شيء انتظره" },
    { text: "ولا ان الوقت اللي نقضيه مع بعض بيصير من اجمل اوقاتي" },
    { text: "لكن هذا اللي صار" },
    { text: "وبعد كل هذا جاء يوم 19 اوت 2026" },
    { text: "اليوم اللي قلت لك فيه اللي كان في قلبي" },
    { text: "احبك يا سارة", big: true },
    { text: "واتمنى تكون هذي مجرد بداية لاشياء كثيرة حلوة بيننا" }
  ];

  /* مقاطع الانترو */
  const introSteps = [
    { mark: "R",            cls: "" },
    { mark: "R + S",        cls: "" },
    { mark: "R ♥ S",        cls: "", heart: true },
    { mark: "رؤوف × سارة",  cls: "is-ar" },
    { mark: "19.08.2026",   cls: "is-date" }
  ];
  const introLines = [
    "قصة بدات بطريقة عادية",
    "لكنها صارت تعني لي الكثير"
  ];

  /* =======================================================
     2. HELPERS
     ======================================================= */
  const $  = (s, c) => (c || document).querySelector(s);
  const $$ = (s, c) => Array.prototype.slice.call((c || document).querySelectorAll(s));
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const isTouch = window.matchMedia('(hover:none)').matches;

  /* Detect if an image file actually exists; only then reveal the slot. */
  function tryLoad(img) {
    return new Promise(function (resolve) {
      const src = img.dataset.src || img.getAttribute('src');
      if (!src) return resolve(false);
      const probe = new Image();
      probe.onload = function () {
        if (img.dataset.src) img.src = src;
        resolve(true);
      };
      probe.onerror = function () { resolve(false); };
      probe.src = src;
    });
  }

  function activateSlots(root) {
    $$('.ph img', root || document).forEach(function (img) {
      tryLoad(img).then(function (ok) {
        if (ok) img.closest('.ph').classList.add('has-photo');
      });
    });
  }

  /* =======================================================
     3. INTRO
     ======================================================= */
  const intro     = $('#intro');
  const stage     = $('#introStage');
  const lineEl    = $('#introLine');
  const enterBtn  = $('#enterBtn');
  const skipBtn   = $('#skipBtn');
  const ui        = $('#ui');
  let introDone   = false;
  let timers      = [];

  function setMark(step) {
    stage.innerHTML = '';
    const s = document.createElement('span');
    s.className = 'intro__mark ' + step.cls;
    if (step.heart) {
      s.innerHTML = 'R <i>&#9829;</i> S';
    } else {
      s.textContent = step.mark;
    }
    stage.appendChild(s);
  }

  function runIntro() {
    if (reduced) { showEnter(); setMark(introSteps[4]); lineEl.textContent = introLines[1]; lineEl.classList.add('is-on'); return; }
    let t = 0;
    introSteps.forEach(function (step, i) {
      timers.push(setTimeout(function () { setMark(step); }, t));
      t += i === introSteps.length - 1 ? 1500 : 1250;
    });
    introLines.forEach(function (txt, i) {
      timers.push(setTimeout(function () {
        lineEl.classList.remove('is-on');
        timers.push(setTimeout(function () {
          lineEl.textContent = txt;
          lineEl.classList.add('is-on');
        }, 420));
      }, t + i * 2200));
    });
    timers.push(setTimeout(showEnter, t + introLines.length * 2200 - 700));
  }

  function showEnter() { enterBtn.classList.add('is-on'); }

  function closeIntro() {
    if (introDone) return;
    introDone = true;
    timers.forEach(clearTimeout);
    intro.classList.add('is-gone');
    document.body.classList.remove('is-locked');
    ui.classList.add('is-on');
    ui.setAttribute('aria-hidden', 'false');
    setTimeout(function () { intro.style.display = 'none'; }, 1300);
    window.scrollTo(0, 0);
  }

  enterBtn.addEventListener('click', closeIntro);
  skipBtn.addEventListener('click', function () { timers.forEach(clearTimeout); closeIntro(); });

  /* =======================================================
     4. LETTER  (built from data so it stays editable)
     ======================================================= */
  (function buildLetter() {
    const body = $('#letterBody');
    const frag = document.createDocumentFragment();
    loveLetter.forEach(function (l) {
      const p = document.createElement('p');
      if (l.big) p.className = 'big';
      p.textContent = l.text;
      p.setAttribute('data-reveal', '');
      frag.appendChild(p);
    });
    body.appendChild(frag);
  })();

  /* =======================================================
     4b. THREAD — the conversation, rebuilt as typography
         (same words, no phone UI, no screenshot)
     ======================================================= */
  (function buildThread() {
    const body = $('#threadBody');
    if (!body) return;
    const t = $('#threadTime');
    if (t) t.textContent = chatMeta.time;

    chatThread.forEach(function (m) {
      if (m.who === 'reply') {
        const r = document.createElement('span');
        r.className = 'thread__reply mono';
        r.textContent = m.text;
        body.appendChild(r);
        return;
      }
      const row = document.createElement('div');
      row.className = 'msg msg--' + m.who;

      // split trailing emoji run so it can breathe on its own line
      const parts = m.text.match(/^([\s\S]*?)\s*([\p{Extended_Pictographic}\uFE0F\u200D\s]*)$/u);
      const words = (parts && parts[1]) ? parts[1].trim() : m.text;
      const emo   = (parts && parts[2]) ? parts[2].trim() : '';

      if (words) {
        const w = document.createElement('span');
        w.className = 'msg__t';
        w.textContent = words;
        row.appendChild(w);
      }
      if (emo) {
        const e = document.createElement('span');
        e.className = 'msg__e';
        e.textContent = emo;
        row.appendChild(e);
      }
      body.appendChild(row);
    });
  })();

  /* =======================================================
     5. GALLERY  (masonry, only real photos)
     ======================================================= */
  const galleryItems = [];

  (function buildMemories() {
    const wrap = $('#memList');
    if (!wrap) return;
    memories.forEach(function (m) {
      const item = document.createElement('article');
      item.className = 'mem__item mem__item--' + (m.kind || 'line');
      item.setAttribute('data-reveal', '');

      const head = document.createElement('div');
      head.className = 'mem__meta';
      head.innerHTML =
        '<span class="mono mem__no">' + (m.no || '') + '</span>' +
        (m.date ? '<span class="mono mem__date">' + m.date + '</span>' : '');

      const h = document.createElement('h3');
      h.className = 'mem__title';
      h.textContent = m.title || '';

      const p = document.createElement('p');
      p.className = 'mem__text';
      p.textContent = m.text || '';

      item.appendChild(head);
      item.appendChild(h);
      item.appendChild(p);
      wrap.appendChild(item);
    });
  })();

  /* الصورتين فقط تفتحان في العارض */
  (function buildPortraits() {
    Object.keys(portraits).forEach(function (k) {
      const probe = new Image();
      probe.onload = function () {
        galleryItems.push({ src: portraits[k], cap: k === 'sara' ? 'سارة' : 'رؤوف', date: '' });
      };
      probe.src = portraits[k];
    });
  })();

  activateSlots();

  /* conversation album click */
  $$('[data-lightbox]').forEach(function (el) {
    el.addEventListener('click', function () {
      const src = el.getAttribute('data-lightbox');
      let idx = galleryItems.findIndex(function (g) { return g.src === src; });
      if (idx < 0) { galleryItems.push({ src: src, cap: 'conversation', date: '' }); idx = galleryItems.length - 1; }
      openLB(idx);
    });
  });

  /* =======================================================
     6. LIGHTBOX
     ======================================================= */
  const lb      = $('#lightbox');
  const lbImg   = $('#lbImg');
  const lbCap   = $('#lbCap');
  const lbCount = $('#lbCount');
  let lbIndex   = 0;

  function openLB(i) {
    if (!galleryItems.length) return;
    lbIndex = (i + galleryItems.length) % galleryItems.length;
    const item = galleryItems[lbIndex];
    lbImg.src = item.src;
    lbImg.alt = item.cap;
    lbImg.classList.remove('is-zoomed');
    lbCap.textContent = item.cap;
    lbCount.textContent = (lbIndex + 1) + ' / ' + galleryItems.length;
    lb.hidden = false;
    requestAnimationFrame(function () { lb.classList.add('is-on'); });
    document.body.style.overflow = 'hidden';
  }
  function closeLB() {
    lb.classList.remove('is-on');
    document.body.style.overflow = '';
    setTimeout(function () { lb.hidden = true; lbImg.src = ''; }, 380);
  }
  function stepLB(d) { openLB(lbIndex + d); }

  $('#lbClose').addEventListener('click', closeLB);
  $('#lbPrev').addEventListener('click', function () { stepLB(-1); });
  $('#lbNext').addEventListener('click', function () { stepLB(1); });
  lb.addEventListener('click', function (e) { if (e.target === lb || e.target.id === 'lbStage') closeLB(); });
  lbImg.addEventListener('click', function (e) { e.stopPropagation(); lbImg.classList.toggle('is-zoomed'); });

  document.addEventListener('keydown', function (e) {
    if (lb.hidden) return;
    if (e.key === 'Escape') closeLB();
    // RTL page: keep arrows intuitive to the visual direction
    if (e.key === 'ArrowRight') stepLB(-1);
    if (e.key === 'ArrowLeft') stepLB(1);
  });

  /* swipe */
  (function swipe() {
    let x0 = null, y0 = null;
    lb.addEventListener('touchstart', function (e) {
      x0 = e.changedTouches[0].clientX; y0 = e.changedTouches[0].clientY;
    }, { passive: true });
    lb.addEventListener('touchend', function (e) {
      if (x0 === null) return;
      const dx = e.changedTouches[0].clientX - x0;
      const dy = e.changedTouches[0].clientY - y0;
      if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.4) stepLB(dx > 0 ? -1 : 1);
      x0 = y0 = null;
    }, { passive: true });
  })();

  /* =======================================================
     7. SCROLL REVEALS
     ======================================================= */
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        const el = en.target;
        // stagger siblings a touch — feels hand-timed, not mechanical
        const sibs = Array.prototype.slice.call(el.parentNode.children).filter(function (n) {
          return n.hasAttribute && (n.hasAttribute('data-reveal') || n.hasAttribute('data-reveal-slow'));
        });
        const k = Math.max(0, sibs.indexOf(el));
        el.style.transitionDelay = (k * 0.11) + 's';
        el.classList.add('is-in');
        io.unobserve(el);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });

    $$('[data-reveal],[data-reveal-slow]').forEach(function (el) { io.observe(el); });

    // big word reveal (ch03)
    const word = $('[data-reveal-word]');
    if (word) {
      $$('span', word).forEach(function (s) { s.innerHTML = '<i>' + s.textContent + '</i>'; });
      new IntersectionObserver(function (e, o) {
        if (e[0].isIntersecting) { word.classList.add('is-in'); o.disconnect(); }
      }, { threshold: 0.4 }).observe(word);
    }

    // confession final line — waits, then breathes in
    const fin = $('[data-final]');
    if (fin) {
      new IntersectionObserver(function (e, o) {
        if (e[0].isIntersecting) {
          setTimeout(function () { fin.classList.add('is-in'); }, reduced ? 0 : 900);
          o.disconnect();
        }
      }, { threshold: 0.55 }).observe(fin);
    }
  } else {
    $$('[data-reveal],[data-reveal-slow],[data-final]').forEach(function (el) { el.classList.add('is-in'); });
  }

  /* =======================================================
     8. CHAPTER TRACKER + PROGRESS
     ======================================================= */
  const chapters = $$('[data-chapter]');
  const numEl = $('#uiChapterNum');
  const nameEl = $('#uiChapterName');
  const bar = $('#progressBar');
  let ticking = false;

  function onScroll() {
    const y = window.scrollY;
    const h = document.documentElement.scrollHeight - window.innerHeight;
    bar.style.width = (h > 0 ? Math.min(100, (y / h) * 100) : 0) + '%';

    const mid = y + window.innerHeight * 0.45;
    let cur = null;
    chapters.forEach(function (c) { if (c.offsetTop <= mid) cur = c; });
    if (cur) {
      const n = cur.getAttribute('data-chapter');
      const nm = cur.getAttribute('data-chapter-name');
      if (numEl.textContent !== n) numEl.textContent = n;
      if (nameEl.textContent !== nm) nameEl.textContent = nm;
    }

    // parallax (desktop only, very light)
    if (!reduced && !isTouch) {
      $$('[data-parallax]').forEach(function (el) {
        const r = el.getBoundingClientRect();
        if (r.bottom < -200 || r.top > window.innerHeight + 200) return;
        const sp = parseFloat(el.getAttribute('data-parallax')) || 0.1;
        const off = (r.top + r.height / 2 - window.innerHeight / 2) * -sp;
        el.style.transform = 'translate3d(0,' + off.toFixed(1) + 'px,0)';
      });
    }
    ticking = false;
  }

  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
  }, { passive: true });
  window.addEventListener('resize', onScroll, { passive: true });
  onScroll();

  /* handmade tilts — set once from markup, so nothing looks machine-uniform */
  $$('[data-tilt]').forEach(function (el) {
    const deg = parseFloat(el.getAttribute('data-tilt'));
    if (!isNaN(deg)) el.style.rotate = deg + 'deg';
  });

  /* =======================================================
     9. COUNTER
     ======================================================= */
  (function counter() {
    const start = new Date(loveStory.firstConfession + 'T00:00:00');
    const d = $('#cDays'), h = $('#cHours'), m = $('#cMins'), s = $('#cSecs');
    const pad = function (n) { return n < 10 ? '0' + n : '' + n; };

    function tick() {
      let diff = Date.now() - start.getTime();
      const future = diff < 0;
      diff = Math.abs(diff);
      const days = Math.floor(diff / 86400000);
      const hrs  = Math.floor(diff / 3600000) % 24;
      const min  = Math.floor(diff / 60000) % 60;
      const sec  = Math.floor(diff / 1000) % 60;
      d.textContent = days;
      h.textContent = pad(hrs);
      m.textContent = pad(min);
      s.textContent = pad(sec);
      const head = $('.counter__head .mono');
      if (future && head) head.textContent = 'الى 19.08.2026';
    }
    tick();
    setInterval(tick, 1000);
  })();

  /* =======================================================
     10. MUSIC
     ======================================================= */
  (function music() {
    const btn = $('#playerBtn');
    const audio = $('#audio');
    const label = $('.player__label', btn);
    const nextBtn = $('#playerNext');
    let track = 0;
    let missing = false;
    let fade = null;

    audio.src = playlist[0].src;
    audio.loop = false; // move through the playlist instead

    function fail() {
      missing = true;
      label.textContent = 'ضع اغنيتنا هنا';
      btn.style.opacity = '.55';
      if (nextBtn) nextBtn.hidden = true;
    }
    audio.addEventListener('error', fail);

    function fadeTo(target, done) {
      clearInterval(fade);
      fade = setInterval(function () {
        const d = target - audio.volume;
        if (Math.abs(d) < 0.04) {
          audio.volume = target; clearInterval(fade);
          if (done) done();
          return;
        }
        audio.volume = Math.max(0, Math.min(1, audio.volume + (d > 0 ? 0.04 : -0.06)));
      }, 80);
    }

    function play() {
      const p = audio.play();
      if (p && p.catch) p.catch(fail);
      audio.volume = 0;
      btn.classList.add('is-playing');
      label.textContent = playlist[track].name;
      if (nextBtn) nextBtn.hidden = playlist.length < 2;
      fadeTo(0.62);
    }
    function pause() {
      fadeTo(0, function () {
        audio.pause();
        btn.classList.remove('is-playing');
        label.textContent = 'شغل اغنيتنا';
      });
    }

    btn.addEventListener('click', function () {
      if (missing) return;
      if (audio.paused) play(); else pause();
    });

    function skip() {
      track = (track + 1) % playlist.length;
      audio.src = playlist[track].src;
      play();
    }
    if (nextBtn) nextBtn.addEventListener('click', function (e) { e.stopPropagation(); skip(); });
    audio.addEventListener('ended', skip);
  })();

  /* =======================================================
     11. BACK TO TOP
     ======================================================= */
  $('#upBtn').addEventListener('click', function () {
    window.scrollTo({ top: 0, behavior: reduced ? 'auto' : 'smooth' });
  });

  /* =======================================================
     12. GO
     ======================================================= */
  runIntro();

  // expose for quick edits from console
  window.OurStory = { loveStory: loveStory, memories: memories, conversations: conversations };
})();
