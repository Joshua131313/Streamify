import type { UseQueryResult } from "@tanstack/react-query";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type { TMDBRawShow } from "../../types/TMDBShowType";
import type { TMDBRawMovie } from "../../types/TMDBMovieType";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { useMemo } from "react";
import type { TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb.ts";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    count?: number;
}
export const useRecommendedMedia = (props: Props) : TMDBMediaQueryResult => {
    const { mediaType, mediaId, count } = props
      
    const query = useTMDBQuery<TMDBListResponse>({
        endpoint: `/${mediaType}/${mediaId}/recommendations`,
        params: {
            page: 1
        },
        enabled: !!mediaId
    });

    const recommended = useMemo<TMDBMedia[]>(() => {
        return normalizeTMDBMedia(query.data?.results, count);
    }, [query]);

    return {
        ...query,
        media: recommended ?? []
    }
}