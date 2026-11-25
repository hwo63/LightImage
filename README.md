# LightImage cho macOS

LightImage là dự án miễn phí và mã nguồn mở, phát hành theo [giấy phép MIT](LICENSE).

Ứng dụng chỉnh ảnh native viết bằng SwiftUI, AppKit và Core Image. Bản 1.5 bổ sung ba mặt nạ tự động cho bầu trời, chủ thể và hậu cảnh. Ứng dụng chạy cục bộ và giữ nguyên ảnh gốc.

Trong **Chỉnh ảnh → Chân dung**, chọn ảnh thu nhỏ của một khuôn mặt hoặc chọn **Tất cả** rồi kéo **Làm sáng da**, **Làm mịn da**, **Thon mặt** và **Thon eo**. Apple Vision phân tích ảnh trên máy. Khi eo bị che, dùng **Chọn vùng eo…** và kéo qua hai mép eo. Thon eo là biến dạng cục bộ, nên ở mức cao các đường nền sát người cũng có thể cong. Các chỉnh sửa chân dung được lưu theo từng ảnh và áp dụng khi xuất.

## Mặt nạ tự động

Mở **Chỉnh theo vùng** (⇧⌘M), chọn **Thêm mặt nạ** rồi chọn **Bầu trời**, **Chủ thể** hoặc **Hậu cảnh**. Lớp phủ hồng hiển thị vùng đã chọn. Kéo các thanh phơi sáng, tương phản, độ bão hòa và nhiệt độ màu như với mặt nạ cọ. Bỏ chọn **Hiện vùng chọn** để xem màu ảnh.

Trong bản 1.5.1, chọn một mặt nạ tự động có sẵn rồi dùng **Tô** để thêm vùng thiếu hoặc **Tẩy** để bớt vùng bị lấn. Chỉnh **Cỡ cọ** để sửa sát viền. **Đặt lại nét sửa** đưa vùng chọn về kết quả nhận diện ban đầu và giữ các thanh chỉnh của mặt nạ.

Trong bản 1.5.2, dùng thanh thu phóng hoặc chụm/mở hai ngón trên trackpad để phóng tới 8× so với vừa khung. Chọn **Kéo ảnh** để đưa mép cần sửa vào giữa, rồi chọn **Chỉnh vùng** để tô hoặc tẩy ở mức phóng hiện tại. **Vừa khung** đưa toàn ảnh về giữa. Từ bản 1.5.3, khi đang **Chỉnh vùng**, giữ **Space** và kéo để di chuyển ảnh tạm thời. Thả Space để dùng tiếp **Tô** hoặc **Tẩy** đang chọn.

Từ bản 1.5.4, **Tô** và **Tẩy** có mức **Độ mềm cọ** và **Độ đậm cọ** riêng. Độ mềm quyết định cách nét mờ dần về rìa, còn độ đậm quyết định lượng vùng chọn thêm hoặc bớt trong một nét. Hai thanh này áp dụng cho nét tiếp theo.

Từ bản 1.5.5, bật **Bám viền** cho **Tô** hoặc **Tẩy** trên mặt nạ tự động. Giữ tâm cọ ở phía viền muốn sửa. Cọ dựa trên màu và ranh giới trong ảnh xem trước để giảm lem, nên nền và tóc tiệp màu vẫn có thể khó tách. Nét sửa đã bám viền được lưu cùng mặt nạ và dùng lại khi xuất. Trong bản 1.5.6, khi bật **Bám viền**, mỗi cọ có thanh **Độ nhạy bám viền** riêng từ 0–100%. Tăng mức để dừng ở chỗ đổi màu nhẹ. Mức 50% giữ độ bám của bản trước. Mức mới áp dụng cho nét tiếp theo.

Trong bản 1.5.7, rê chuột trên ảnh khi bật **Bám viền** để xem vùng cọ sẽ tác động tại vị trí đó. Màu xanh là vùng sẽ tô thêm, màu cam là vùng sẽ tẩy bớt. Lớp xem trước dùng cỡ, độ mềm, độ đậm và độ nhạy của cọ đang chọn. Từ bản 1.5.8, lớp phủ cập nhật dọc theo nét trong lúc kéo. Thả chuột để áp dụng cả nét.

Từ bản 1.5.9, nhấn **Esc** khi vẫn giữ chuột để bỏ nét **Tô** hoặc **Tẩy** đang kéo. Lớp xem trước của nét biến mất ngay và mặt nạ giữ nguyên khi thả chuột.

Từ bản 1.5.10, dùng **Hoàn tác** và **Làm lại** dưới cọ **Tô/Tẩy** để bỏ hoặc khôi phục từng nét trên mặt nạ đang chọn. Sau khi hoàn tác, vẽ nét mới trên mặt nạ đó sẽ bỏ các nét đang chờ làm lại.

Từ bản 1.5.11, trong bảng **Chỉnh theo vùng**, dùng **⌘Z** để hoàn tác và **⇧⌘Z** để làm lại từng nét trên mặt nạ đang chọn.

Apple Vision tách chủ thể ngay trên Mac. Hậu cảnh là phần còn lại của mask chủ thể, gồm cả trời nếu có. Nhận diện trời dựa trên màu, độ sáng, chi tiết và liên kết với phần trên khung hình. Cảnh bầu trời bị che hoặc bề mặt sáng giống trời có thể cho vùng chọn thiếu hoặc thừa. Dữ liệu vùng chọn được lưu theo ảnh và dùng lại khi xuất.

## Công cụ trong 1.4

- **Chỉnh theo vùng** (⇧⌘M) mở trình chỉnh riêng để vẽ gradient thẳng, gradient tròn hoặc tô và tẩy bằng cọ. Mỗi mặt nạ có phơi sáng, tương phản, độ bão hòa, nhiệt độ và cường độ riêng. Có thể đảo vùng, ẩn đường dẫn hoặc bật/tắt từng mặt nạ. Mặt nạ được vẽ trên ảnh trước khi cắt/lật để bám đúng vùng khi đổi khung hình.
- **Kéo vạch** (⇧Y) đặt ảnh trước và sau chồng lên nhau để so sánh chi tiết.
- **Cắt & Xoay** có lật ngang, lật dọc và cân thẳng ±45°. Cân thẳng tự thu khung để tránh góc trống.
- **Hiệu ứng** có hạt film với cỡ và độ thô riêng. Vùng tối góc có thêm tâm, độ mềm, độ tròn và bảo vệ vùng sáng. Nhập được các tham số XMP tương ứng.
- **Ảnh → Tạo bản sao ảo** (⇧⌘D) tạo một phiên bản chỉnh sửa độc lập trong thư viện, dùng chung tệp gốc. Mỗi bản sao xuất được thành tệp riêng.

Các công cụ này được xây dựng trong LightImage từ tham khảo tính năng của [Lightcraft](https://github.com/storytold/lightcraft). Nhập mặt nạ từ preset Lightroom hiện chưa được hỗ trợ.

## Mở ứng dụng

Chọn bản cài đặt trong [GitHub Releases](https://github.com/hwo63/LightImage/releases) nếu bạn có quyền truy cập kho. Bản dựng sẵn dành cho Mac Apple Silicon chạy macOS 14 trở lên.

- **DMG**. Mở tệp `.dmg`, kéo **LightImage.app** vào **Applications**, rồi mở ứng dụng từ đó.
- **ZIP**. Giải nén tệp `.app.zip`, chuyển **LightImage.app** vào **Applications**, rồi mở ứng dụng.

Bản cài thử được ký ad-hoc. macOS có thể chặn bản tải về vì thiếu chữ ký Developer ID và notarization. Bản tự build nằm ở `dist/LightImage.app`.

1. Chọn **Nhập ảnh** hoặc kéo ảnh/thư mục vào cửa sổ. Có thể thử bằng **Khám phá với ảnh minh họa**.
2. Chọn **Nhập preset**, chọn `.xmp`, `.lrtemplate`, hoặc thư mục chứa các preset. Giải nén ZIP trước khi nhập.
3. Chọn ảnh, rồi bấm preset ở cột trái. Các mục được hỗ trợ được áp dụng vào ảnh và có thể chỉnh tiếp ở cột phải.
4. Chọn **Trước / Sau** để so sánh cùng khung hình, rồi **Xuất ảnh**.

Có hai preset mẫu do dự án tạo trong `Samples/`: `Golden Hour.xmp` và `Silver Matte.lrtemplate`. Chúng dùng để thử chức năng nhập, không phải preset do Adobe cung cấp.

## Tính năng hiện có

- Nhập nhiều ảnh và thư mục đệ quy; bỏ qua đường dẫn trùng. Hỗ trợ JPEG, PNG, HEIC, TIFF và các RAW mà macOS giải mã được.
- Thư viện dạng lưới, dải ảnh, tìm tên, đánh dấu, đánh giá 0–5 sao, lọc ảnh đã chỉnh.
- Chỉnh sửa không phá hủy: phơi sáng, tương phản, highlights/shadows, whites/blacks, cân bằng trắng, vibrance, saturation.
- HSL 8 nhóm màu; trộn sáng đen trắng; đường cong tổng và từng kênh RGB có thể kéo điểm.
- Texture, clarity, dehaze, sharpen có radius/detail/masking, giảm nhiễu sáng và màu, vignette được mô phỏng bằng Core Image.
- Calibration RGB/ShadowTint, split toning và Color Grading (midtones/global/luminance/blending/balance), parametric curve và ba ranh giới vùng sáng.
- AutoTone theo histogram. Đây là thuật toán của LightImage, không phải AutoTone/AI của Adobe.
- Xoay 90°, cắt theo tỷ lệ, điều chỉnh kích thước/vị trí khung cắt; scale và dịch chuyển X/Y theo preset. Vùng nằm ngoài ảnh sau dịch chuyển có thể trong suốt.
- So sánh trước/sau, cuộn chuột để phóng to hoặc thu nhỏ ảnh xem trước, kéo ảnh khi đã phóng to, hoàn tác/làm lại trong phiên, sao chép/dán và đồng bộ chỉnh sửa cho các ảnh đang lọc.
- Trong **Trước / Sau** và **Kéo vạch**, cuộn hoặc kéo ảnh để cập nhật cả hai bản cùng lúc. Khi đã phóng to ở chế độ **Kéo vạch**, kéo ngay trên vạch để đổi vị trí vạch hoặc kéo ngoài vạch để di chuyển ảnh.
- Sáu preset tích hợp, nhập preset Lightroom theo lô, cường độ preset, lưu preset riêng và báo các thông số chưa hỗ trợ.
- Tự lưu thư viện, chỉnh sửa, đánh giá và preset. Chọn lại tệp nếu ảnh gốc đã bị chuyển chỗ.
- Xuất từng ảnh hoặc cả bộ lọc: JPEG/PNG 8-bit, TIFF 16-bit; màu sRGB; độ phân giải gốc hoặc giới hạn cạnh dài. Không sao chép EXIF/GPS. Xuất theo lô tự tránh trùng tên.

## Mức tương thích preset Lightroom

Đọc namespace Camera Raw trong XMP, thuộc tính XML, phần tử XML, tên/nhóm dạng `rdf:Alt`, và đường cong dạng `rdf:Seq`. Đọc bảng dữ liệu Lua trong `.lrtemplate`; **không thực thi Lua**. Các thông số không có trong preset được giữ nguyên trên ảnh.

| Nhóm | Thông số được đọc và áp dụng |
| --- | --- |
| Ánh sáng | `Exposure2012`, `Contrast2012`, `Highlights2012`, `Shadows2012`, `Whites2012`, `Blacks2012`; alias `Exposure`, `Contrast` |
| Cân bằng trắng | `Temperature`, `Tint`, `IncrementalTemperature`, `IncrementalTint` |
| Màu | `Vibrance`, `Saturation`, `HueAdjustment*`, `SaturationAdjustment*`, `LuminanceAdjustment*` |
| Đường cong | `ToneCurvePV2012`, các kênh Red/Green/Blue, `ToneCurve` cũ |
| Đen trắng | `ConvertToGrayscale`, `Treatment`, `GrayMixer*` |
| Calibration | `RedHue/Saturation`, `GreenHue/Saturation`, `BlueHue/Saturation`, `ShadowTint` |
| Parametric | `ParametricShadows/Darks/Lights/Highlights`, `ParametricShadowSplit/MidtoneSplit/HighlightSplit` |
| Grading | `SplitToningShadowHue/Saturation`, `SplitToningHighlightHue/Saturation`, `SplitToningBalance`, `ColorGradeMidtoneHue/Sat`, `ColorGradeGlobalHue/Sat`, `ColorGradeShadow/Midtone/Highlight/GlobalLum`, `ColorGradeBlending` |
| Tự động / khử sương | `AutoTone`, `Dehaze` |
| Chi tiết | `Clarity2012`/`Clarity`, `Texture`, `Sharpness`, `SharpenRadius`, `SharpenDetail`, `SharpenEdgeMasking` |
| Giảm nhiễu | `LuminanceSmoothing`, `LuminanceNoiseReductionDetail/Contrast`, `ColorNoiseReduction`, `ColorNoiseReductionDetail/Smoothness` |
| Transform | `PerspectiveScale`, `PerspectiveX`, `PerspectiveY` |
| Film và góc ảnh | `GrainAmount/Size/Frequency`, `PostCropVignetteAmount/Midpoint/Feather/Roundness/HighlightContrast`, `VignetteAmount` |

Các phép xử lý này là **xấp xỉ bằng thuật toán của LightImage**. Đường cong dùng nội suy cubic Hermite không vượt quá điểm điều khiển; ánh sáng/HSL qua LUT 64³ có cache; white balance tuyệt đối áp dụng sau giải mã ảnh. Vì vậy cùng thông số có thể cho màu khác Lightroom, đặc biệt trên RAW. TIFF 16-bit là định dạng đầu ra, không có nghĩa bộ xử lý tái tạo được toàn bộ dải sáng/độ chính xác của Adobe.

Chưa hỗ trợ profile/LUT Adobe, DCP, lens correction, sửa quang sai màu tự động/Defringe, nhập mặt nạ Lightroom, healing, AI denoise và crop nhập từ preset. Các mục chưa hỗ trợ đang bật sẽ được báo khi nhập/áp dụng. Giá trị số 0 ở mọi cách viết (`+0`, `0.00`), metadata `ShortName`/`SortName`, các ngưỡng Defringe khi Amount bằng 0 và `LensProfileSetup` khi lens correction tắt không tạo cảnh báo; preset chỉ có mục chưa hỗ trợ sẽ không áp dụng giả. Các thông số phụ được hỗ trợ có giá trị mặc định đúng: scale 100%, sharpen radius 1, các ranh giới 25/50/75. Blending của split-toning cũ không có trường ColorGradeBlending được đặt về 100 theo ngữ nghĩa tương thích cũ của Adobe.

Chưa nhập `.lrcat`, preset từ DNG, ZIP, thư viện Photos hoặc đồng bộ Adobe Cloud. Chưa có panorama/HDR merge, tethering, in ấn, bản đồ, quản lý keyword/collection nâng cao, chỉnh phối cảnh, cắt tự do bằng chuột hay hiển thị RAW đầy đủ ở mức 1:1. Ảnh xem trước giới hạn cạnh dài 2400 px; ảnh xuất luôn đọc lại nguồn đầy đủ. Hỗ trợ RAW phụ thuộc camera và phiên bản hệ điều hành, chưa được kiểm chứng bằng mẫu RAW riêng của người dùng.

## Dữ liệu và thao tác

Ứng dụng tham chiếu đường dẫn ảnh gốc, không sao chép ảnh vào thư viện. Giữ các ảnh gốc ở vị trí ổn định. **Bỏ khỏi thư viện** chỉ xóa mục trong catalog, không xóa ảnh trên ổ đĩa. Hoàn tác trong phiên không tồn tại sau khi thoát; chỉnh sửa cuối cùng vẫn được lưu.

Dữ liệu lưu trong `~/Library/Application Support/HWO.LightImage/catalog.json`, ghi nguyên tử. Nếu catalog lỗi hoặc khác phiên bản, ứng dụng báo lỗi và giữ tệp đó nguyên vẹn thay vì ghi đè. Có thể mở thư mục dữ liệu bằng menu Help. Sao lưu thư mục này cùng các ảnh gốc để giữ thư viện. Biến môi trường `LIGHTIMAGE_DATA_DIR` cho phép dùng thư mục dữ liệu riêng khi phát triển.

| Phím tắt | Thao tác |
| --- | --- |
| ⌘O | Nhập ảnh |
| ⇧⌘I | Nhập preset |
| ⌘E | Xuất ảnh |
| ⌘Z / ⇧⌘Z | Hoàn tác / Làm lại |
| ⇧⌘C / ⇧⌘V | Sao chép / Dán chỉnh sửa |
| `\` | So sánh trước/sau |
| P | Đánh dấu ảnh |
| ⌃0…5 | Đặt số sao |
| ⌘← / ⌘→ | Chuyển ảnh |

## Biên dịch và kiểm thử

Không có dependency bên ngoài. Cần Xcode hoặc Swift toolchain có macOS SDK.

### Build từ mã nguồn bằng Xcode

1. Mở `Package.swift` trong Xcode.
2. Chọn scheme **LightImage** và đích **My Mac**.
3. Bấm **Product → Build** (⌘B) để biên dịch hoặc **Product → Run** (⌘R) để chạy.

### Đóng gói từ Terminal

```sh
./scripts/build-app.sh
./scripts/package-release.sh
./scripts/test.sh
```

Script build tạo app bundle, biểu tượng, preset mẫu và chữ ký ad-hoc trong `dist/LightImage.app`. Script đóng gói tạo thêm `.dmg` và `.app.zip` trong `dist/releases/<phiên bản>/`.

Phiên bản có dạng `YY.major.patch (build DDMM.HHMMSS)`. Hai số `major.patch` lấy từ `CFBundleShortVersionString` trong `Resources/Info.plist`. Script điền năm và thời điểm build theo giờ Việt Nam.

22 kiểm thử XCTest bao gồm XMP với namespace thay đổi, tên localized, metadata lồng nhau, đường cong, `.lrtemplate`, dữ liệu lỗi/DTD, giữ thông số không có trong preset, cường độ bằng 0, catalog round-trip, thay đổi pixel thật, pipeline trung tính, cắt/xoay, xuất JPEG/PNG/TIFF 16-bit, ghi đè tệp xuất và giữ nguyên nguồn. Kiểm thử kết xuất cần truy cập các dịch vụ đồ họa macOS; sandbox công cụ chặn GPU có thể khiến Core Image trả ảnh rỗng. Bộ kiểm thử mới còn kiểm chứng hue đi qua 0°, default/amount, calibration giữ xám trung tính, phân vùng parametric và grading, màu đen trắng được toning, giảm nhiễu màu giữ luminance, radius/detail/masking ảnh hưởng riêng, AutoTone/dehaze, transform giữ kích thước canvas, và cập nhật preset giữ ID. Kiểm thử tệp preset riêng được bật bằng biến `LIGHTIMAGE_PRESET_FIXTURE`; không phân phối lại preset của người dùng trong mã nguồn.

Mã chính: `Sources/LightImageCore` chứa model, parser và pipeline ảnh; `Sources/LightImage` chứa app native, giao diện, catalog, hàng đợi preview và xuất ảnh. Không gọi dịch vụ mạng.

Tài liệu tham khảo: [Adobe Camera Raw XMP namespace](https://developer.adobe.com/xmp/docs/xmp-namespaces/crs/), [Apple CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter), [danh sách RAW của macOS 27](https://support.apple.com/en-au/127493).

## Cập nhật preset đã nhập từ bản 1.0

Nhập lại chính tệp `.xmp`/`.lrtemplate` cũ: LightImage cập nhật preset tương ứng, giữ ID và không tạo bản trùng. Sau đó bấm preset để áp dụng lại cho ảnh. Chỉnh sửa trên ảnh không bị tự ý thay bằng preset mới. Từ bản 1.1, catalog giữ bản dữ liệu nguồn của preset để những lần nâng cấp parser sau có thể đọc thêm trường chưa hỗ trợ; bản 1.0 không lưu những giá trị đã bỏ qua nên cần nhập lại một lần.

Với tệp **TRẮNG HỒNG 3** trên máy này, bản 1.1 đọc **78 thông số** (kể cả giá trị mặc định/0). Còn đúng bốn cảnh báo: `AutoLateralCA`, `CameraProfile` (trong tệp là `Default Color`), `LensProfileEnable`, `LensProfileSetup`. Không thay profile Adobe bằng một LUT tự đặt rồi báo đã hỗ trợ. Số thông số đọc được không phải thước đo độ chính xác màu.

Calibration bản 1.2 dùng tọa độ primary xy quanh D65 và ma trận nghịch đảo giữ điểm trắng; thang slider được hiệu chỉnh thực nghiệm, không phải thuật toán/profile Adobe. Grading dùng soft-light với các vùng sáng chồng lấn, parametric dùng các vùng chuyển tiếp mượt, dehaze dùng ước lượng ánh sáng khí quyển/dark channel, noise reduction tách luma/chroma. RAW vẫn được giải mã bằng Apple, không phải Adobe; các khác biệt demosaic/profile/tone mapping vẫn tồn tại.

Tài liệu ngữ nghĩa bổ sung: [Adobe Color Grading và tương thích Split Toning](https://blog.adobe.com/en/publish/2020/10/20/introducing-color-grading), [Adobe tone/parametric curve](https://helpx.adobe.com/si/camera-raw/desktop/using/make-color-tonal-adjustments-camera.html), [Adobe sharpening và noise reduction](https://helpx.adobe.com/in/lightroom-classic/desktop/process-and-develop-photos/retouch-photos.html).

Bộ lọc không gian hiện dùng Core Image Kernel Language (API còn chạy trên máy đã kiểm thử nhưng Apple đã đánh dấu deprecated). Cần chuyển sang Metal kernels khi chuẩn bị phát hành lâu dài. Nếu kernel không khởi tạo được, ứng dụng báo lỗi thay vì bỏ qua hiệu ứng. Script đóng gói tạo bundle mới rồi đổi tên bundle cũ, không sửa executable của phiên đang chạy; mở lại ứng dụng để dùng bản mới.


## Sửa màu trong 1.2 và kiểm chứng với ảnh Lightroom

- Basic tone điều chỉnh độ sáng chung thay vì bẻ riêng từng kênh RGB; Blacks không cộng một lớp xám vào điểm đen.
- HSL luminance thay đổi độ sáng theo tỷ lệ, giảm tác động ở màu gần xám và dành khoảng sáng cho vùng highlight để tránh bạc màu/cắt kênh.
- Calibration giữ điểm trắng D65, sửa độ mạnh tương đối các primary; cân bằng trắng JPEG tương đối được tách khỏi đơn vị Kelvin/tint tuyệt đối.
- JPEG được ghi EXIF ColorSpace=sRGB; PNG được ghi sRGB rendering intent. Không sao chép metadata cá nhân từ ảnh gốc.

Đối chiếu cục bộ ngày 12/11/2026 bằng ba ảnh người dùng cung cấp, cùng preset **TRONG TRẺO 3** (xác nhận từ XMP nhúng trong ảnh Lightroom). Ảnh tham chiếu có ICC Display P3; đưa về sRGB trước khi đo Lab D65/CIEDE2000. Ảnh xuất thật 6240×4160 được thu về 960×640 bằng cùng bộ lọc Lanczos để đo:

| Kết quả | ΔE00 trung bình | Trung vị | Phân vị 95% |
| --- | ---: | ---: | ---: |
| LightImage cũ do người dùng gửi | 9.71 | 9.84 | 14.84 |
| LightImage 1.2 | 4.76 | 4.38 | 9.29 |

Sai lệch trung bình giảm khoảng **51%**, cả 9 ô của lưới 3×3 đều cải thiện. Đây là phép kiểm tra trên **một ảnh/preset dùng trong quá trình hiệu chỉnh**, không phải bộ kiểm định độc lập hay bằng chứng giống Lightroom 1:1. Chưa kiểm chứng khả năng tổng quát trên các ảnh/preset khác; sắc xanh, màu da, vùng sáng và các màu ngoài sRGB vẫn có thể lệch. Không có ảnh tham chiếu, LUT học từ ảnh hoặc dữ liệu cá nhân được nhúng vào ứng dụng. Mọi ảnh đang chỉnh sẽ được kết xuất lại bằng thuật toán mới, nhưng các thông số và tệp gốc không bị thay đổi.

Công cụ đối chiếu chạy cục bộ (Python chỉ cần cho QA, ứng dụng không phụ thuộc Python):

```sh
# JSON là Adjustments của ảnh, hoặc dùng công cụ này với bộ dữ liệu QA riêng.
swift run -c release LightImageDiagnostics input.jpg settings.json output-directory result full
# Cần pillow, numpy, scikit-image trong môi trường Python riêng.
python scripts/compare-colors.py lightroom.jpg old.jpg new.jpg --output metrics.json
# Có thể dùng --max-mean để đặt ngưỡng hồi quy cho từng bộ ảnh tham chiếu.
```

Bộ Swift tests có thêm kiểm tra giữ sắc độ của basic tone, HSL không nâng xám, tính hữu hạn/điểm trắng ở Calibration cực đại, hướng white balance và thẻ sRGB đầu ra. 25 kiểm thử chạy đạt; một fixture preset riêng chỉ chạy khi đặt `LIGHTIMAGE_PRESET_FIXTURE`.

## Màu TRONG TRẺO 3 trong bản 1.6.1

Khi áp lại bản XMP TRONG TRẺO 3 đã đối chiếu, LightImage dùng thêm hiệu chỉnh màu sRGB đo từ một cặp ảnh gốc và ảnh xuất Lightroom. Hệ số phụ thuộc vào màu điểm ảnh và cường độ preset. Bảng màu này hoạt động trong cả xem trước lẫn xuất ảnh.
