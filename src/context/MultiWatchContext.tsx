import { createContext, useContext, useEffect, useState, type Dispatch, type SetStateAction } from "react";
import { DefaultGameProps, type GameProps } from "../types/sports/sportsTypes";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";

export const defaultWindowSize = {
    w: 400,
    h: 250
}
export const defaultWindowPosition = {
    x: 100,
    y: 100
}
type WindowState = "closed" | "minimized" | "fullscreen" | "opened";

interface MultiWatchWindowState {
    windowState: WindowState;
    lastWindowState: WindowState;
    lastWindowOpenedSize: { w: number, h: number };
    lastWindowOpenedPosition: { x: number, y: number };
}

interface QuickWatchContextType {
    multiWatch: GameProps[];
    multiWatchWindowState: MultiWatchWindowState;
    toggleGameInMultiWatch: (game: GameProps) => void;
    removeGameFromMultiWatch: (game: GameProps) => void;
    addGameToMultiWatch: (game: GameProps) => void;
    adjustMultiWatchWindow: (windowState: WindowState) => void;
    isGameInMultiWatch: (game: GameProps) => boolean;
    adjustMultiWindowSize: (w: number, h: number) => void;
    adjustMultiWindowPosition: (x: number, y: number) => void;
}


const MultiWatchContext = createContext<QuickWatchContextType | null>(null);

export const QuickWatchProvider = ({ children }: { children: React.ReactNode }) => {
    const [multiWatchWindowState, setMultiWatchWindowState] = useState<MultiWatchWindowState>({
        lastWindowOpenedSize: defaultWindowSize,
        lastWindowOpenedPosition: defaultWindowPosition,
        lastWindowState: "closed",
        windowState: "closed"
    });
    const [multiWatch, setMultiWatch] = useState<GameProps[]>([]);
    const { append, remove, get, clear } = useLocalStorage();

    const clearMultiWatch = () => {
        setMultiWatch([]);
        clear("multi-watch");
    }

    const removeGameFromMultiWatch = (game: GameProps): void => {
        if (!game.id) return;

        if (isGameInMultiWatch(game)) {
            remove<GameProps>("multi-watch", (g) => g.id === game.id);
            setMultiWatch(prev => [...prev.filter(g => g.id !== game.id)])
        }
    }

    const addGameToMultiWatch = (game: GameProps): void => {
        // make sure game is valid
        if (!game.id) return;

        // only add games that are not already in the list
        if (!isGameInMultiWatch(game)) {
            append("multi-watch", game);
            setMultiWatch(prev => [...prev, game]);
            setMultiWatchWindowState((prev) => ({
                ...prev,
                windowState: prev.windowState === "closed" ? "opened" : prev.windowState,
                lastWindowState: prev.windowState === "closed" ? "opened" : prev.windowState,
            }));
        }
    }

    const toggleGameInMultiWatch = (game: GameProps): void => {
        if (isGameInMultiWatch(game)) {
            removeGameFromMultiWatch(game);
        }
        else {
            addGameToMultiWatch(game);
        }
    }
    const adjustMultiWindowSize = (w: number, h: number) => {
        setMultiWatchWindowState((prev) => {
            if (prev.windowState === "fullscreen") return prev;

            return {
                ...prev,
                lastWindowOpenedSize: { w, h },
            };
        });
    };
    const adjustMultiWindowPosition = (x: number, y: number) => {
        setMultiWatchWindowState((prev) => {
            if (prev.windowState === "fullscreen") return prev;
            const maxX = window.innerWidth - prev.lastWindowOpenedSize.w;
            return {
                ...prev,
                lastWindowOpenedPosition: { x : Math.max(0, Math.min(x, maxX)), y },
            };
        });
    };

    const adjustMultiWatchWindow = (windowState: WindowState) => {
        setMultiWatchWindowState((prev) => {
            if (windowState === "closed") {
                clearMultiWatch();
            }

            return {
                ...prev,
                lastWindowState: prev.windowState,
                windowState,
            };
        });
    };

    const isGameInMultiWatch = (game: GameProps): boolean => {
        return multiWatch.some(g => g.id === game.id);
    }

    useEffect(() => {
        const games = get("multi-watch", [DefaultGameProps]);
        // get will return [DefaultGameProps] if no entries found
        // so only setMultiWatch if games were found
        if (games[0]?.id !== undefined) {
            setMultiWatch(games);
        }
    }, [])


    return (
        <MultiWatchContext.Provider value={{
            multiWatch,
            multiWatchWindowState,
            removeGameFromMultiWatch,
            addGameToMultiWatch,
            toggleGameInMultiWatch,
            isGameInMultiWatch,
            adjustMultiWatchWindow,
            adjustMultiWindowSize,
            adjustMultiWindowPosition,
        }}>
            {children}
        </MultiWatchContext.Provider>
    );
};

export const useMultiWatch = () => {
    const ctx = useContext(MultiWatchContext);
    if (!ctx) {
        throw new Error("useQuickWatch must be used inside QuickWatchProvider");
    }
    return ctx;
};