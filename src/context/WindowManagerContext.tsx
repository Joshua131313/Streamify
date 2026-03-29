import {
    createContext,
    useContext,
    useEffect,
    useState,
    type ReactNode,
} from "react";

export type WindowState = "closed" | "minimized" | "fullscreen" | "opened";

export interface WindowData {
    windowState: WindowState;
    lastWindowState: WindowState;

    size: { w: number; h: number };
    position: { x: number; y: number };
    zIndex: number;
}

type WindowMap = Record<string, WindowData>;

interface WindowManagerContextType {
    windows: WindowMap;

    openWindow: (id: string) => void;
    closeWindow: (id: string) => void;
    minimizeWindow: (id: string) => void;
    toggleFullscreen: (id: string) => void;
    toggleWindow: (id: string) => void;
    getWindowIndex: (id: string) => number;
    setWindowSize: (id: string, w: number, h: number) => void;
    setWindowPosition: (id: string, x: number, y: number) => void;
    windowIsOpen: (id: string) => boolean;
}

const WindowManagerContext =
    createContext<WindowManagerContextType | null>(null);

let zCounter = 999;
let spawnOffset = 0;

export const WindowManagerProvider = ({
    children,
}: {
    children: ReactNode;
}) => {
    const [windows, setWindows] = useState<WindowMap>({});
    const createWindowIfMissing = (id: string): WindowData => {
        const OFFSET_STEP = 30;

        const x = 100 + spawnOffset * OFFSET_STEP;
        const y = window.scrollY + (100 + spawnOffset * OFFSET_STEP);

        spawnOffset++;

        // optional: reset if too far
        if (spawnOffset > 10) spawnOffset = 0;

        return {
            windowState: "opened",
            lastWindowState: "closed",
            size: { w: 500, h: 350 },
            position: { x, y },
            zIndex: zCounter++,
        };
    };

    const getWindowIndex = (id: string) => {
        const ids = Object.entries(windows)
            .filter(([_, w]) => w.windowState !== "closed")
            .map(([key]) => key);

        return ids.indexOf(id);
    };

    const updateWindow = (id: string, updater: (w: WindowData) => WindowData) => {
        setWindows((prev) => {
            const existing = prev[id] || createWindowIfMissing(id);

            return {
                ...prev,
                [id]: updater(existing),
            };
        });
    };
    const windowIsOpen = (id: string) => {
        return Object.entries(windows)
            .filter(([_, w]) => (w.windowState !== "minimized" && w.windowState !== "closed"))
            .some(([key]) => key === id);
    };
    const openWindow = (id: string) =>
        updateWindow(id, (w) => ({
            ...w,
            windowState:
                w.lastWindowState && w.lastWindowState !== "closed"
                    ? w.lastWindowState
                    : "opened",
            lastWindowState: w.windowState,
            zIndex: zCounter++,
        }));

    const closeWindow = (id: string) =>
        updateWindow(id, (w) => ({
            ...w,
            windowState: "closed",
            lastWindowState: w.windowState,
        }));

    const toggleWindow = (id: string) =>
        updateWindow(id, (w) => {
            let nextState: WindowState;

            switch (w.windowState) {
                case "opened":
                case "fullscreen":
                    nextState = "minimized";
                    break;

                case "minimized":
                    nextState =
                        w.lastWindowState && w.lastWindowState !== "closed"
                            ? w.lastWindowState
                            : "opened";
                    break;

                case "closed":
                default:
                    nextState = "opened";
                    break;
            }

            return {
                ...w,
                windowState: nextState,
                lastWindowState: w.windowState,
                zIndex: zCounter++,
            };
        });
    const minimizeWindow = (id: string) =>
        updateWindow(id, (w) => ({
            ...w,
            windowState: "minimized",
            lastWindowState: w.windowState,
        }));

    const toggleFullscreen = (id: string) =>
        updateWindow(id, (w) => ({
            ...w,
            windowState:
                w.windowState === "fullscreen" ? "opened" : "fullscreen",
            lastWindowState: w.windowState,
            zIndex: zCounter++,
        }));

    const setWindowSize = (id: string, w: number, h: number) =>
        updateWindow(id, (win) => {
            if (win.windowState === "fullscreen") return win;
            return { ...win, size: { w, h } };
        });

    const setWindowPosition = (id: string, x: number, y: number) =>
        updateWindow(id, (win) => {
            if (win.windowState === "fullscreen") return win;

            const maxX = window.innerWidth - win.size.w;

            return {
                ...win,
                position: {
                    x: Math.max(0, Math.min(x, maxX)),
                    y: Math.max(0, y),
                },
            };
        });

    // useEffect(() => {
    //     const hasFullscreen = Object.values(windows).some(
    //         (w) => w.windowState === "fullscreen"
    //     );

    //     if (hasFullscreen) {
    //         document.body.style.overflow = "hidden";
    //     } else {
    //         document.body.style.overflow = "";
    //     }

    //     return () => {
    //         document.body.style.overflow = "";
    //     };
    // }, [windows]);

    return (
        <WindowManagerContext.Provider
            value={{
                windows,
                openWindow,
                closeWindow,
                minimizeWindow,
                toggleFullscreen,
                toggleWindow,
                setWindowSize,
                setWindowPosition,
                getWindowIndex,
                windowIsOpen
            }}
        >
            {children}
        </WindowManagerContext.Provider>
    );
};

export const useWindowManager = () => {
    const ctx = useContext(WindowManagerContext);
    if (!ctx) throw new Error("useWindowManager must be used inside provider");
    return ctx;
};