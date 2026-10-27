# Titanium Image Cropping Tool

An easy to crop images to different scales. Based on the awesome [TOCropViewController](https://github.com/TimOliver/TOCropViewController) library. Currently iOS only (!)

<img src="./example.png" height="600" alt="Example Screenshot" />
<img src="./IMG_0827.PNG" height="600" alt="Example Screenshot rounded cropping" />

## Requirements

- [x] Titanium SDK 12.0.0+
- [x] iOS 26.0+ (version 3.1.0)

## Methods

### `showCropDialog`

#### Parameters

- `image` (String, Ti.Blob, Ti.File)
- `croppingStyle` 'circular' or 'default' (String) in not set 'default' is selected

- `aspectRatio` A dictionary `{x, y}` of positive integers to describe the width-to-height ratio. Note: Prior to v3.0.0,
you could also apply a preset, but these have been removed in the native library.
- `aspectRatioLocked` (Boolean, default `false`) Hides the aspect ratio picker and locks the crop box to `aspectRatio`. When the ratio is omitted or invalid, locked cropping defaults to 1:1. Resizing, reset, and image rotation preserve the ratio, including its width/height order. Circular cropping remains 1:1.

For a fixed square crop:

```js
ImageCrop.showCropDialog({
  image: 'test.jpg',
  aspectRatioLocked: true
});
```

For a fixed 4:3 crop, also pass `aspectRatio: { x: 4, y: 3 }`. Omit `aspectRatioLocked` or set it to `false` to retain the existing picker behavior.

## Events

- `done`
  - Attributes: `image` (Ti.Blob, if finished cropping), `cancel` (`true` if cancelled, `false` if completetd)
- `close`
- `error`
  - Attributes: `code` (`invalidImage` or `presentationFailed`), `message` (String).
  - A failed opening releases the pending dialog so a later call can try again.

## Notes

- If opening the image crop dialog from a modal window, please set the `modalStyle: Ti.UI.iOS.MODAL_PRESENTATION_OVER_CURRENT_FULL_SCREEN` property (thanks to [designbymind](https://github.com/designbymind)!)
- Dialog creation and presentation run on the main thread. If the photo picker or another controller is transitioning, the module waits for it to finish and resolves the presenter again. If no attached, stable presenter becomes available within five seconds, it emits `error` with code `presentationFailed`.
- `done` fires before dismissal; use `close` to open the next window or crop dialog. The module clears its busy state before firing `close`.

## Example

```js
import ImageCrop from 'ti.imagecrop';

ImageCrop.addEventListener('done', event => {
  if (event.cancel) {
    return;
  }

  win.add(Ti.UI.createImageView({ height: 400, image: event.image }));
});

ImageCrop.addEventListener('close', event => {
  // Open other windows after the close has been triggered
  // to prevent transition glitches
});

const win = Ti.UI.createWindow({
  backgroundColor: '#fff'
});

const btn = Ti.UI.createButton({
  title: 'Show crop dialog'
});

btn.addEventListener('click', () => {
  ImageCrop.showCropDialog({
    image: 'test.jpg'
  });
});

win.add(btn);
win.open();
```

## License

MIT

## Author

Hans Knöchel
