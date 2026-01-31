import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeShow } from "../../utils/normalizeTMDB";
import type { TMDBShowMedia } from "../../types/TMDBMediaType";
import type { TMDBRawShow } from "../../types/TMDBShowType";


export const useShow = ({showId} : {showId: string}) : [TMDBShowMedia | null, boolean, any] => {

    const [data, loading, err] = useTMDBQuery<TMDBRawShow>({
        endpoint: `/tv/${showId}`,
        params: {
            append_to_response: "videos,credits,images"
        }
    })
    console.log('show', data)
    const show = data ? normalizeShow(data) : null; 
    return [show, loading, err]
}