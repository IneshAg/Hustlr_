{
  {
    flutter_js;
  }
}
{
  {
    flutter_build_config;
  }
}

_flutter.loader.load({
  config: {
    // Safer on problematic GPUs/browsers and avoids CanvasKit context-loss crashes.
    renderer: "html",
  },
});
