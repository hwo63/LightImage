const range = document.querySelector('#comparison-range');
const stage = document.querySelector('#comparison-stage');

function updateComparison() {
  stage.style.setProperty('--split', `${range.value}%`);
  range.setAttribute('aria-valuetext', `${range.value}% ảnh trước`);
}

range.addEventListener('input', updateComparison);
updateComparison();

const player = document.querySelector('#intro-player');
const play = document.querySelector('.intro-play');
if (player && play) {
  play.hidden = false;
  play.addEventListener('click', () => {
    player.play().catch(() => player.focus({ preventScroll: true }));
  });
  player.addEventListener('playing', () => {
    if (document.activeElement === play) player.focus({ preventScroll: true });
    play.hidden = true;
  }, { once: true });
}

const copy = document.querySelector('.copy-button');
if (navigator.clipboard?.writeText) {
  copy.hidden = false;
  let reset;
  copy.addEventListener('click', async () => {
    clearTimeout(reset);
    try {
      await navigator.clipboard.writeText(copy.parentElement.querySelector('code').textContent);
      copy.textContent = 'Đã sao chép';
    } catch {
      copy.textContent = 'Chọn lệnh để sao chép';
    }
    reset = setTimeout(() => { copy.textContent = 'Sao chép'; }, 2000);
  });
}

const motion = window.matchMedia('(prefers-reduced-motion: no-preference)');
if ('IntersectionObserver' in window && motion.matches) {
  const revealObserver = new IntersectionObserver((entries, observer) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      if (motion.matches) entry.target.classList.add('is-revealed');
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.08 });

  for (const section of document.querySelectorAll('[data-reveal]')) {
    revealObserver.observe(section);
  }
}

async function setLatestDownload() {
  try {
    const response = await fetch('https://api.github.com/repos/hwo63/LightImage/releases/latest', {
      credentials: 'omit',
      headers: { Accept: 'application/vnd.github+json' },
    });
    if (!response.ok) return;

    const release = await response.json();
    const tag = release?.tag_name;
    if (release?.draft || release?.prerelease || typeof tag !== 'string' || !/^v\d{2}\.\d+\.\d+$/.test(tag)) return;
    if (!Array.isArray(release.assets)) return;

    const version = tag.slice(1);
    const versionLabels = document.querySelectorAll('[data-release-version]');
    const currentParts = versionLabels[0]?.textContent.trim().split('.') ?? [];
    for (const [index, part] of version.split('.').entries()) {
      const difference = Number(part) - Number(currentParts[index] ?? 0);
      if (difference < 0) return;
      if (difference > 0) break;
    }
    const dmg = release.assets.find((asset) => asset?.state === 'uploaded' && typeof asset.name === 'string'
      && asset.name.startsWith(`LightImage-${version}-`) && asset.name.endsWith('-macOS-arm64.dmg'));
    if (!dmg) return;

    const download = `https://github.com/hwo63/LightImage/releases/download/${tag}/${encodeURIComponent(dmg.name)}`;
    if (dmg.browser_download_url !== download) return;

    for (const link of document.querySelectorAll('[data-latest-dmg]')) link.href = download;
    for (const label of versionLabels) label.textContent = version;
  } catch {
    // The HTML links still download the bundled page's release when the API is unavailable.
  }
}

setLatestDownload();
