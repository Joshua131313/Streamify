import {
    createContext,
    useContext,
    useEffect,
    useState,
    type ReactNode,
} from "react";
import { DefaultGameProps, type GameProps } from "../types/sports/sportsTypes";
import { useLocalStorage } from "../hooks/utilHooks/useLocalStorage";
import { gameIsWatchable } from "../utils/sports/sportsUtils";

interface MultiWatchContextType {
    multiWatch: GameProps[];
    toggleGameInMultiWatch: (game: GameProps) => void;
    removeGameFromMultiWatch: (game: GameProps) => void;
    addGameToMultiWatch: (game: GameProps) => void;
    isGameInMultiWatch: (game: GameProps) => boolean;
    clearMultiWatch: () => void;
}

const MultiWatchContext = createContext<MultiWatchContextType | null>(null);

export const MultiWatchProvider = ({ children }: { children: ReactNode }) => {
    const [multiWatch, setMultiWatch] = useState<GameProps[]>([]);
    const { append, remove, set, clear, get } = useLocalStorage();
    console.log(multiWatch)
    const clearMultiWatch = () => {
        setMultiWatch([]);
        clear("multi-watch");
    };

    const isGameInMultiWatch = (game: GameProps): boolean => {
        return multiWatch.some((g) => g.id === game.id);
    };

    const removeGameFromMultiWatch = (game: GameProps): void => {
        if (!game.id) return;

        if (isGameInMultiWatch(game)) {
            remove<GameProps>("multi-watch", (g) => g.id === game.id);
            setMultiWatch((prev) => prev.filter((g) => g.id !== game.id));
        }
    };

    const addGameToMultiWatch = (game: GameProps): void => {
        if (!game.id) return;

        if (!isGameInMultiWatch(game)) {
            append("multi-watch", game);
            setMultiWatch((prev) => [...prev, game]);
        }
    };

    const toggleGameInMultiWatch = (game: GameProps): void => {
        if (isGameInMultiWatch(game)) {
            removeGameFromMultiWatch(game);
        } else {
            addGameToMultiWatch(game);
        }
    };
    
    useEffect(() => {
        const games = get<GameProps[]>("multi-watch", []);

        const validGames = games.filter(g =>
            gameIsWatchable(g.startTime)
        );

        if (validGames.length !== games.length) {
            set("multi-watch", validGames);
        }

        setMultiWatch(validGames);
    }, []);

    useEffect(() => {
        const interval = setInterval(() => {
            setMultiWatch(prev => {
                const valid = prev.filter(g =>
                    // status is stale since it is the status of when the user stored it into multiwatch
                    gameIsWatchable(g.startTime)
                );

                if (valid.length !== prev.length) {
                    set("multi-watch", valid); 
                }

                return valid;
            });
        }, 60000);

        return () => clearInterval(interval);
    }, []);

    return (
        <MultiWatchContext.Provider
            value={{
                multiWatch,
                removeGameFromMultiWatch,
                addGameToMultiWatch,
                toggleGameInMultiWatch,
                isGameInMultiWatch,
                clearMultiWatch,
            }}
        >
            {children}
        </MultiWatchContext.Provider>
    );
};

export const useMultiWatch = () => {
    const ctx = useContext(MultiWatchContext);
    if (!ctx) {
        throw new Error("useMultiWatch must be used inside MultiWatchProvider");
    }
    return ctx;
};