(function () {
  var BP_EM = 76.1875; // match Material breakpoint used in CSS

  function isSmall() {
    return window.matchMedia("(max-width: " + BP_EM + "em)").matches;
  }

  function collapsePrimaryNav(opts) {
    opts = opts || {};
    var keepCurrent = !!opts.keepCurrent;
    var toggles = document.querySelectorAll('.md-nav--primary input.md-nav__toggle');
    toggles.forEach(function (t) {
      try {
        if (keepCurrent) {
          var nav = t.parentElement && t.parentElement.querySelector(':scope > .md-nav');
          var expanded = nav && nav.getAttribute('aria-expanded') === 'true';
          if (expanded) return; // leave current section open
        }
        t.checked = false; // collapse
        t.indeterminate = false;
      } catch (_) {
        // no-op
      }
    });
  }

  function init() {
    if (isSmall()) collapsePrimaryNav({ keepCurrent: false });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Optional: re-apply on resize for dynamic viewport changes
  window.addEventListener('resize', function () {
    if (isSmall()) collapsePrimaryNav({ keepCurrent: false });
  });
})();

