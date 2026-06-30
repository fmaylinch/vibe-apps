// Reports the document's content height to the host (via the "hostHeight"
// message handler) whenever it changes, so the native view can size to fit.
// Injected at document end.
(function () {
    function report() {
        var h = Math.ceil(document.body ? document.body.scrollHeight
                                        : document.documentElement.scrollHeight);
        window.webkit.messageHandlers.hostHeight.postMessage(h);
    }
    window.addEventListener("load", report);
    if (document.body && window.ResizeObserver) {
        new ResizeObserver(report).observe(document.body);
    }
    report();
})();
