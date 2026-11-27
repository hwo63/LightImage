<p align="center">
  <img src="docs/assets/lightimage-icon.png" width="100" height="100" alt="LightImage icon">
</p>

<h1 align="center">LightImage</h1>

<p align="center">
  <a href="README.md">Tiếng Việt</a> · <strong>English</strong>
</p>

<p align="center">A free, open-source photo editor for macOS with Adobe Lightroom preset support.</p>

<p align="center">
  <a href="https://github.com/hwo63/LightImage/releases/latest">Download the latest release</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#comparison-with-lightroom-and-lightcraft">Feature comparison</a> ·
  <a href="#build-from-source-with-xcode">Build with Xcode</a> ·
  <a href="LICENSE">MIT License</a>
</p>

Import Lightroom presets, edit photos, and export them on your Mac. LightImage saves adjustments for each photo and preserves the original files.

## Installation

LightImage **26.1.1** is available for **Intel and Apple Silicon Macs running macOS 14 or later**. This release adds an English interface and a **Settings** window for language, updates, and export defaults. [View the 26.1.1 release](https://github.com/hwo63/LightImage/releases/tag/v26.1.1)

Open ** → About This Mac** to check your chip or processor, then choose the matching file under **Assets**.

| Mac | DMG installer suffix | ZIP archive suffix |
| --- | --- | --- |
| Apple Silicon (Apple M-series chip) | `macOS-arm64.dmg` | `macOS-arm64.app.zip` |
| Intel | `macOS-x86_64.dmg` | `macOS-x86_64.app.zip` |

### Install from a DMG

1. Open the [latest release](https://github.com/hwo63/LightImage/releases/latest) and expand **Assets**.
2. Download the matching `.dmg` and open it.
3. Drag **LightImage.app** to **Applications** in the installer window.
4. Open **LightImage** from **Applications**. You can then eject the LightImage disk image in Finder.

### Install from a ZIP archive

1. Download the matching `.app.zip` from **Assets**.
2. Extract **LightImage.app**.
3. Move the app to **Applications** and open it there.

### First launch if macOS blocks LightImage

GitHub builds are ad-hoc signed and are distributed without Apple notarization. If the download prompt offers **Open**, click it. If macOS blocks the app because it cannot verify the developer, follow these steps after confirming that your download came from the official releases page. [LightImage GitHub Releases](https://github.com/hwo63/LightImage/releases)

1. In Finder, open **Applications** and double-click **LightImage.app**. Close the prompt if macOS blocks the launch.
2. Open ** → System Settings → Privacy & Security**.
3. Scroll to **Security**, find the message about **LightImage**, and click **Open Anyway**.
4. Authenticate if prompted, then click **Open** in the confirmation dialog. This exception applies to LightImage only.

If **Open Anyway** is missing, try opening LightImage from **Applications** again and return to **Privacy & Security**. You can also [build the app from source with Xcode](#build-from-source-with-xcode). [Apple's guide to opening apps](https://support.apple.com/en-us/102445)

### In-app updates

Starting with **26.0.2**, LightImage checks GitHub Releases at launch and periodically while running. Once the new package has downloaded and its signature has been verified, **Restart to Update** appears in the lower-right corner. Click it to save the library, install the update, and reopen LightImage. LightImage keeps using the installed version until you click the button, even if you quit and reopen the app.

Starting with **26.0.5**, choose **LightImage → Check for Updates…** to check immediately. LightImage reports whether the latest version is already installed, an update is ready, or an error occurred. The updater finds the latest public GitHub release and verifies the downloaded package before offering to install it.

Starting with **26.1.1**, you can also check for updates and toggle automatic checks in **Settings → Updates**.

If **Restart to Update** is missing in **26.0.3** or **26.0.4**, install the latest version manually once. [Download from GitHub](https://github.com/hwo63/LightImage/releases/latest)

If you installed **26.0.1** from GitHub, update manually once. Run LightImage from **Applications** so the updater can replace the installed app.

## Getting started

1. Click **Import Photos** (⌘O), or drag photos or folders into the app. Choose **Try a Demo Photo** to explore the editor.
2. Click **Import Presets** (⇧⌘I), then choose `.xmp` or `.lrtemplate` files or a folder of presets. Extract ZIP archives first.
3. Select a photo and click a preset in the left sidebar. Use **Preset Amount** or the controls on the right to fine-tune the result. Try importing the two presets in [Samples](Samples).
4. Use **Before / After** or **Split View** to compare. Scroll to zoom and drag to examine details. Both previews share the same zoom and position.
5. Click **Export Photos** (⌘E) and choose a format, size, and destination. You can export one photo or a group from the current filter.

## LightImage settings

From **26.1.1**, choose **LightImage → Settings…** (⌘,) or click the gear icon in the toolbar. In the Vietnamese interface, the menu item is **Cài đặt…**.

- Choose **Tiếng Việt** or **English** to switch the interface language. LightImage remembers your choice between sessions.
- Under **Updates**, view the installed version, select **Check for Updates…**, or toggle automatic checks. When a verified update is ready, choose **Restart to Update** when you want to install it.
- Under **Export Defaults**, set the format, JPEG quality, maximum long edge, and whether to reveal exported photos in Finder. You can override these settings for each export.

## Features

| Area | Tools |
| --- | --- |
| Library | Import photos and folders, search by name, flag and rate photos, and create virtual copies. |
| Light and color | Exposure, contrast, highlights, shadows, white balance in Kelvin for RAW or on a relative scale for JPEG/TIFF, tint, eight-channel HSL, RGB curves, black and white, color grading, and calibration. |
| Detail and effects | Enhance detail, reduce luminance and color noise, and restore faded contrast or reduce small spots in older photos. Use Texture, Clarity, Dehaze, film grain, and vignettes. |
| Object removal and Lens Blur | Paint over an object for LaMa to fill. Lens Blur detects the subject and lets you set the background blur. |
| Local adjustments | Automatically mask the sky, subject, or background. Paint and erase directly with an edge-aware brush and a live preview. Adjust brush softness, strength, and edge sensitivity. |
| Portraits | Detect faces and brighten or smooth skin, reduce small blemishes, and slim individual faces. Slim waists, arms, and legs, or paint a mask for hair adjustments. Apple Vision runs on the Mac. |
| Comparison | Use Before / After or Split View with synchronized zoom and position to inspect colors and details. |
| Framing and export | Crop to an aspect ratio, rotate, flip, and straighten. Export JPEG, PNG, or 16-bit TIFF in sRGB for the current photo, selected photos, all edited photos, or filtered photos. |

Under **White Balance & Color**, drag **Temperature** left to cool the photo or right to warm it. You can also enter a value directly. RAW uses Kelvin and starts from the camera’s as-shot white balance. JPEG and TIFF use a relative scale from −100 to +100. Use **Tint** to correct a color cast, or click **Reset** to restore the original white balance.

In **Local Adjustments**, use **Paint** or **Erase** to refine mask edges. Press **Esc** during a brush stroke to cancel it. Hold **Space** and drag to pan. Use **⌘Z** and **⇧⌘Z** to undo or redo strokes on the selected mask.

Open **Portrait** to detect faces in the photo. Choose **All Faces**, then move the **Brighten Skin**, **Smooth Skin**, **Remove Blemishes**, or **Slim Face** slider to apply the same value to every face. Each slider changes one setting. Click a thumbnail to edit a person separately, or choose **Use Shared Settings for This Face** to restore the common values for that person. **Remove Blemishes** follows **Smooth Skin** until you set it separately. It targets small blemishes while protecting eye and lip detail.

Use **Slim Arms** or **Slim Legs** when the corresponding joints are detected. To change hair color, choose **Edit Hair…**, paint over the hair, and adjust **Hair Hue**, **Exposure**, or **Saturation**. Use **Erase** to refine the edges.

In **Split View**, drag the divider to move it. When zoomed in, drag outside the divider to pan the photo. Click **Fit** to show the entire image.

### Object removal, Lens Blur, and restoration

- **AI Object Removal**. Paint over the object and click **Fill with AI**. On first use, LightImage downloads the LaMa Core ML model (about 217 MB). It fills the area on your Mac and preserves the result when you reopen or export the photo. [Core ML model](https://huggingface.co/gumka/lama-coreml) · [LaMa and its Apache 2.0 license](https://github.com/advimman/lama)
- **Lens Blur**. Click **Detect Subject**, then adjust **Background Blur**.
- **Detail & Restoration**. Use **Enhance Detail**, **Luminance Noise Reduction**, **Color Noise Reduction**, or **Restore Old Photo** to bring out detail, reduce noise or small spots, and restore faded contrast.

### Batch editing and export

1. Select photos using the checkboxes in **Library** or the filmstrip. Use **Select Filtered Photos** to select everything currently shown.
2. Click a preset on the left to apply it at 100% to every selected photo. Click **Deselect All** in the filmstrip to return to editing one photo at a time.
3. Open **Export Photos**. Under **Export Scope**, choose **Selected Photos** or **All Edited Photos**, then select a destination folder. **All Edited Photos** includes the entire library, even photos outside the current filter.

## Comparison with Lightroom and LightCraft

LightImage is designed for Mac users who want to use their Lightroom presets in a free, open-source app. Import folders of `.xmp` and `.lrtemplate` files, adjust the preset amount, and check the result in Split View. Your library and edits are stored locally.

| Feature | LightImage | Adobe Lightroom | LightCraft |
| --- | --- | --- | --- |
| Preset support | Imports `.xmp` and `.lrtemplate`, supports adjustable amounts, and lists the settings recognized on import. | Lightroom and Lightroom Classic support presets and profiles in the Camera Raw ecosystem. | Supports XMP and `.lcpreset` presets and reads and writes XMP sidecars. |
| Preset color comparison | Tested against a Lightroom export. The RAW test sample had a mean ΔE00 of **4.32** and a 95th percentile of **8.965**. | The Lightroom export served as the color reference. | Uses its own renderer for XMP settings, so colors can differ from a Lightroom export. |
| Masking and portraits | Automatic masks, edge-aware painting and erasing with a live preview, and on-device skin and body adjustments with Apple Vision. | Supports subject, sky, background, and skin masks through Select People. | Offers brushes, gradients, and color or luminance masks. Select Object and Describe use an optional SAM 3 model. |
| Platform and workflow | Native macOS app under the MIT License. GitHub builds offer **Restart to Update** when a download is ready. | Adobe subscriptions include Lightroom Classic and Lightroom with syncing across devices. | Open-source RAW editor written in Rust for macOS, Windows, Linux, and the web. |

[Lightroom Classic presets](https://helpx.adobe.com/lightroom-classic/desktop/process-and-develop-photos/apply-presets.html) · [Lightroom masking](https://helpx.adobe.com/lightroom/desktop/edit-photos/masking.html) · [Adobe Lightroom plans](https://www.adobe.com/products/photoshop-lightroom/plans.html) · [LightCraft features](https://github.com/storytold/lightcraft#feature-status)

The test used one Canon CR3 RAW photo with **TRONG TRẺO 3** at **100%** in LightImage 26.0.2 and Lightroom. Both exports were converted to sRGB, sampled at 960 × 640, and compared pixel by pixel using CIEDE2000. About 95% of the sampled pixels had a ΔE00 of 8.965 or lower. [Color comparison script](scripts/compare-colors.py)

## Lightroom and RAW compatibility

LightImage reads **XMP** and **LRTEMPLATE** presets, including many tone, white balance, HSL, curve, grading, calibration, sharpening, noise reduction, and vignette settings. Right-click a preset and choose **Show Details** to see which settings LightImage recognized and which are unsupported.

LightImage interprets these settings using its own renderer, so the result can differ from Lightroom, particularly with RAW files and presets that depend on a camera profile. Current limitations include Adobe profiles and LUTs, DCP profiles, automatic lens and chromatic aberration corrections, Lightroom masks, healing, and AI denoising. Import supports individual photos and presets. `.lrcat` catalogs and Adobe Cloud sync are outside the current scope.

The app opens JPEG, PNG, HEIC, TIFF, and other formats. RAW support depends on the camera and macOS decoder. Previews have a maximum long edge of 2400 px. When exporting, LightImage reads the original again and uses full resolution if you choose the original size.

## Data and keyboard shortcuts

The library references photos at their original locations. The catalog and presets are stored in `~/Library/Application Support/HWO.LightImage/`. Choose **Help → Open LightImage Data Folder** to find them. If you move an image to a different folder, choose **Relink Original Photo…** to update its location.

| Shortcut | Action |
| --- | --- |
| ⌘O / ⇧⌘I / ⌘E | Import photos / import presets / export photos |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⇧⌘C / ⇧⌘V | Copy / paste edits |
| `\` / ⇧Y | Before / After or Split View |
| ⇧⌘M | Local Adjustments |
| ⇧⌘D | Create a virtual copy |
| ⌘← / ⌘→ | Move between photos |

## Build from source with Xcode

Build on a Mac with Xcode and the macOS SDK. The Swift package targets macOS 14 or later and uses Swift tools 5.9. The app uses SwiftUI, AppKit, Core Image, and Apple Vision.

1. Download the source using **Code → Download ZIP** and extract it, or clone the repository in Terminal.

   ```sh
   git clone https://github.com/hwo63/LightImage.git
   cd LightImage
   ```

2. Open **Package.swift** in Xcode and wait for the Swift package to load.
3. Select the **LightImage** scheme and the **My Mac** run destination.
4. Choose **Product → Build** (⌘B) to compile or **Product → Run** (⌘R) to launch.

### Build an app or installer from Terminal

Run these commands from the directory containing `Package.swift`.

| Command | Output |
| --- | --- |
| `./scripts/build-app.sh` | Creates `dist/LightImage.app` with the icon, sample presets, and license. |
| `./scripts/package-release.sh` | Builds the app and creates a `.dmg` and `.app.zip` in `dist/releases/<version>/`. |
| `./scripts/test.sh` | Runs the SwiftPM tests for preset import, color processing, masks, portraits, and export. |

The scripts build for the architecture of the host Mac. LightImage displays versions as `YY.major.patch (build DDMM.HHMMSS)`, using Vietnam time for the build stamp.

### Publish a release on GitHub

The workflow in `hwo63/LightImage` runs when `Resources/Info.plist` changes on `main`. Set `CFBundleShortVersionString` to the new `YY.major.patch` value and push the commit to `main`. GitHub Actions runs tests and packages `.app.zip` and `.dmg` files on Apple Silicon and Intel runners. Once both packages are ready, the workflow signs each update package, generates `Release.md` from the commits since the previous tag, and publishes a single GitHub release. You can also rerun **Release LightImage for macOS** from the **Actions** tab.

Set up the signing key once before your first release with this workflow. Run the following from the repository root. It writes the private key to a file readable only by your account and prints the public key.

```sh
swift scripts/sign-update.swift --create-key ~/.lightimage-update-key
```

In **Settings → Secrets and variables → Actions**, save the contents of the private key file as the `LIGHTIMAGE_UPDATE_PRIVATE_KEY` secret and the public key as the `LIGHTIMAGE_UPDATE_PUBLIC_KEY` repository variable. If you are signed in to GitHub CLI, you can pass the private key through stdin with `gh secret set LIGHTIMAGE_UPDATE_PRIVATE_KEY --repo hwo63/LightImage < ~/.lightimage-update-key`.

Keep a secure backup of the private key. Use the same key for future releases so existing installations can verify new downloads. This key signs LightImage update packages. macOS Developer ID signing and notarization are separate distribution steps.

### Source layout

- `Sources/LightImage` contains the macOS interface, library management, import, editing, and export workflows.
- `Sources/LightImageCore` contains preset parsing, image processing, masks, and portrait tools.
- `Sources/LightImageDiagnostics` and `scripts/compare-colors.py` support local color comparisons. The measurement script uses Pillow, NumPy, and scikit-image.
- `Tests/LightImageCoreTests` contains the core tests. Set `LIGHTIMAGE_PRESET_FIXTURE` and `LIGHTIMAGE_PORTRAIT_FIXTURE` to run tests with local samples.
- [`website/`](website/) contains the static project website, images, JavaScript, and video.

## Deploy the website on Cloudflare Pages

In **Workers & Pages**, choose **Create application → Pages → Import an existing Git repository**. Connect GitHub, select `hwo63/LightImage`, and use these settings. [Cloudflare's static HTML deployment guide](https://developers.cloudflare.com/pages/framework-guides/deploy-anything/)

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Framework preset | `None` |
| Root directory | Leave blank to use the repository root |
| Build command | `exit 0` |
| Build output directory | `website` |

Click **Save and Deploy** for the initial deployment. Cloudflare Pages will update the website when new commits reach `main`. Edit the files in `website/` and push your changes to GitHub. [Cloudflare Pages GitHub integration](https://developers.cloudflare.com/pages/configuration/git-integration/github-integration/)

If you originally deployed through **Direct Upload**, create a Pages project with **Git integration** to deploy automatically from GitHub. [Cloudflare Direct Upload documentation](https://developers.cloudflare.com/pages/get-started/direct-upload/)

## License and contributing

LightImage is distributed under the [MIT License](https://github.com/hwo63/LightImage/blob/main/LICENSE). It takes inspiration from Lightroom and [Lightcraft](https://github.com/storytold/lightcraft), and from the idea of using Lightroom presets in an independent editor. When filing a bug in [GitHub Issues](https://github.com/hwo63/LightImage/issues), include the LightImage version, your macOS version, and steps to reproduce it. If you build on a fork, please credit LightImage as a source of inspiration.

## Buy me a coffee ☕

If LightImage helps you and you would like to support the project, scan the QR code below with MoMo or a banking app that supports VietQR. Thank you for using LightImage!

<a href="docs/assets/donate-coffee.png">
  <img src="docs/assets/donate-coffee.png" width="200" alt="MoMo and VietQR code for supporting LightImage">
</a>
