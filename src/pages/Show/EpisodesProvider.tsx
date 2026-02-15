import { createContext, useContext, useState } from "react";
import { useEpisodes } from "../../hooks/mediaHooks/showHooks/useEpisodes";
import type { TMDBShowMedia } from "../../types/TMDBMediaType";
import type { TEpisode } from "../../types/TMDBShowType";

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
}

interface Props {
  show: TMDBShowMedia;
  children: React.ReactNode;
}

const EpisodesContext = createContext<EpisodesContextType | null>(null);

export const EpisodesProvider = ({ show, children }: Props) => {
    const [seasonNumber, setSeasonNumber] = useState(1);
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