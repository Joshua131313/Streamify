import { useEffect, useState } from "react";
import { useWatchHistoryContext } from "../../context/WatchHistoryContext";
import type { TMediaType } from "../../types/tmdb";

export const buildPlayUrl = ({
    mediaType,
    mediaId,
    season,
    episode,
}: {
    mediaType: TMediaType;
    mediaId: number;
    season?: number;
    episode?: number;
}) => {
    const base = `/${mediaType}/${mediaId}?play`;

    if (mediaType === "movie") return base;

    const s = season ?? 1;
    const e = episode ?? 1;

    return `${base}&season=${s}&episode=${e}`;
};

export const usePlayUrl = (mediaId: number, mediaType: TMediaType) => {
    const { getHistoryItem } = useWatchHistoryContext();

    const [state, setState] = useState<{
        url: string;
        season?: number;
        episode?: number;
    }>({
        url: buildPlayUrl({ mediaId, mediaType }),
        season: undefined,
        episode: undefined,
    });

    useEffect(() => {
        let mounted = true;

        const load = async () => {
            const item = await getHistoryItem(
                mediaId,
                mediaType === "movie" ? "movie" : "tv"
            );

            if (!mounted) return;

            const season = item?.season ?? 1;
            const episode = item?.episode ?? 1;

            setState({
                season,
                episode,
                url: buildPlayUrl({
                    mediaId,
                    mediaType,
                    season,
                    episode,
                }),
            });
        };

        load();

        return () => {
            mounted = false;
        };
    }, [mediaId, mediaType, getHistoryItem]);

    return state;
};