import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeShow } from "../../../utils/normalizeTMDB";
import type { TMDBShowMedia } from "../../../types/TMDBMediaType";
import type { TMDBRawShow } from "../../../types/TMDBShowType";
import type { UseQueryResult } from "@tanstack/react-query";

type UseShowResult = UseQueryResult<TMDBRawShow> & {
    show: TMDBShowMedia | null;
}

export const useShow = ({showId} : {showId: string}) : UseShowResult => {

    const query = useTMDBQuery<TMDBRawShow>({
        endpoint: `/tv/${showId}`,
        params: {
            append_to_response: "videos,credits,images"
        },
        enabled: !!showId
    })

    return {
        ...query, 
        show: query.data ? normalizeShow(query.data) : null
    }
}