import { useMemo } from "react";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type {
    TMDBListResponse,
    TMDBMediaQueryResult,
    TMediaType
} from "../../types/tmdb";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
    count?: number;
}

export const useRelatedMedia = (props: Props): TMDBMediaQueryResult => {
    const { mediaType, mediaId, count } = props;

    const relatedQuery = useTMDBQuery<TMDBListResponse>({
        endpoint: `/${mediaType}/${mediaId}/similar`,
        params: {
            page: 1,
        },
        enabled: !!mediaId,
    });

    const relatedMedia = useMemo<TMDBMedia[]>(() => {
        return normalizeTMDBMedia(relatedQuery.data?.results, {
            defaultMediaType: mediaType,
            count,
        });
    }, [relatedQuery.data, mediaType, count]);

    return {
        ...relatedQuery,
        media: relatedMedia ?? [],
    };
};