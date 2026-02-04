import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeShow } from "../../../utils/normalizeTMDB";
import type { TMDBShowMedia } from "../../../types/TMDBMediaType";
import type { TEpisode, TMDBRawShow, TSeason } from "../../../types/TMDBShowType";
import type { UseQueryResult } from "@tanstack/react-query";

type UseEpisodeResult = UseQueryResult<TSeason> & {
    episodes: TEpisode[]
}

export const useEpisodes = ({showId, seasonNumber} : {showId: number, seasonNumber: number}) : UseEpisodeResult => {

    const query = useTMDBQuery<TSeason>({
        endpoint: `/tv/${showId}/season/${seasonNumber}`,
        enabled: !!showId
    });
    return {
        ...query,
        episodes: query.data?.episodes || []
    }
}