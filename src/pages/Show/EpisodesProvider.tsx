import { createContext, useContext, useState, useEffect } from "react";
import { useEpisodes } from "../../hooks/mediaHooks/showHooks/useEpisodes";
import type { TMDBShowMedia } from "../../types/TMDBMediaType";
import type { TEpisode } from "../../types/TMDBShowType";
import { useSearchParams } from "react-router-dom";
import { useWatchHistoryContext } from "../../context/WatchHistoryContext";

interface EpisodesContextType {
    show: TMDBShowMedia;
    episodes: TEpisode[];
    isLoading: boolean;

    seasonNumber: number;
    setSeasonNumber: (n: number) => void;

    search: string;
    setSearch: (s: string) => void;

    direction: "asc" | "desc";
    setDirection: (d: "asc" | "desc") => void;

    currentEpisode: number;
}

interface Props {
    show: TMDBShowMedia;
    children: React.ReactNode;
}

const EpisodesContext = createContext<EpisodesContextType | null>(null);

export const EpisodesProvider = ({ show, children }: Props) => {
    const [searchParams] = useSearchParams();
    const { getHistoryItem } = useWatchHistoryContext();

    const [history, setHistory] = useState<{
        season?: number;
        episode?: number;
    } | null>(null);

    const [seasonNumber, setSeasonNumber] = useState(1);
    const [currentEpisode, setCurrentEpisode] = useState(0);
    const [search, setSearch] = useState("");
    const [direction, setDirection] = useState<"asc" | "desc">("asc");

    useEffect(() => {
        let mounted = true;

        const loadHistory = async () => {
            const item = await getHistoryItem(show.id, "tv");
            if (mounted) {
                setHistory(item ?? null);
            }
        };

        loadHistory();

        return () => {
            mounted = false;
        };
    }, [show.id, getHistoryItem]);

    useEffect(() => {
        const urlSeason = Number(searchParams.get("season"));

        if (urlSeason) {
            setSeasonNumber(urlSeason);
            return;
        }

        if (history?.season) {
            setSeasonNumber(history.season);
        } else {
            setSeasonNumber(1);
        }
    }, [searchParams, history?.season]);

    useEffect(() => {
        if (history?.episode) {
            setCurrentEpisode(history.episode);
        } else {
            setCurrentEpisode(0);
        }
    }, [history?.episode]);

    const { episodes, isLoading } = useEpisodes({
        showId: show.id,
        seasonNumber,
    });

    return (
        <EpisodesContext.Provider
            value={{
                show,
                episodes: episodes ?? [],
                isLoading,

                seasonNumber,
                setSeasonNumber,

                search,
                setSearch,

                direction,
                setDirection,

                currentEpisode
            }}
        >
            {children}
        </EpisodesContext.Provider>
    );
};

export const useEpisodesContext = () => {
    const ctx = useContext(EpisodesContext);
    if (!ctx) {
        throw new Error("useEpisodesContext must be used inside EpisodesProvider");
    }
    return ctx;
};