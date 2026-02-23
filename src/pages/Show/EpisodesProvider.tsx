import { createContext, useContext, useState } from "react";
import { useEpisodes } from "../../hooks/mediaHooks/showHooks/useEpisodes";
import type { TMDBShowMedia } from "../../types/TMDBMediaType";
import type { TEpisode } from "../../types/TMDBShowType";
import { useSearchParams } from "react-router-dom";

/* ---------- Context Type ---------- */
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
    const currentEpisode = Number(searchParams.get("episode") ?? 0);
    const currentSeason = Number(searchParams.get("season") ?? 1);
    const [seasonNumber, setSeasonNumber] = useState(Number(currentSeason));
    const [search, setSearch] = useState("");
    const [direction, setDirection] = useState<"asc" | "desc">("asc");

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