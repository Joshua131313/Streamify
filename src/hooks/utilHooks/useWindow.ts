import { useWindowManager } from "../../context/WindowManagerContext";

export const useWindow = (id: string) => {
    const manager = useWindowManager();

    const window = manager.windows[id];

    return {
        appWindow: window,

        open: () => manager.openWindow(id),
        close: () => manager.closeWindow(id),
        minimize: () => manager.minimizeWindow(id),
        toggleFullscreen: () => manager.toggleFullscreen(id),
        toggleWindow: () => manager.toggleWindow(id),
        getWindowIndex: () => manager.getWindowIndex(id),
        setSize: (w: number, h: number) =>
            manager.setWindowSize(id, w, h),

        setPosition: (x: number, y: number) =>
            manager.setWindowPosition(id, x, y),
        isOpen: manager.windowIsOpen(id)

    };
};