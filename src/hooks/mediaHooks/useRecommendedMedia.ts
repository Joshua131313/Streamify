import type { UseQueryResult } from "@tanstack/react-query";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type { TMDBRawShow } from "../../types/TMDBShowType";
import type { TMDBRawMovie } from "../../types/TMDBMovieType";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { useMemo } from "react";
import type { TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb.ts";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";
import axios from "axios";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    genre: number;
    count?: number;
}
export const useRecommendedMedia = (props: Props) : TMDBMediaQueryResult => {
    const { mediaType, mediaId, genre, count } = props
    const isEnabled = !!mediaId;
    const recommendationsQuery = useTMDBQuery<TMDBListResponse>({
        endpoint: `/${mediaType}/${mediaId}/recommendations`,
        params: {
            page: 1
        },
        enabled: !!mediaId
    });
    const similarQuery = useTMDBQuery<TMDBListResponse>({
        endpoint: `/discover/${mediaType}`,
        params: { page: 1, with_genres: genre },
        enabled:
            isEnabled &&
            !!genre &&
            recommendationsQuery.isSuccess &&
            (recommendationsQuery.data?.results?.length ?? 0) === 0,
    });

    const activeData =
        (recommendationsQuery.data?.results?.length ?? 0) > 0
        ? recommendationsQuery.data
        : similarQuery.data;


    const recommended = useMemo<TMDBMedia[]>(() => {
        return normalizeTMDBMedia(activeData?.results, {defaultMediaType: mediaType, count});
    }, [activeData]);

    return {
        ...recommendationsQuery,
        media: recommended ?? []
    }
}