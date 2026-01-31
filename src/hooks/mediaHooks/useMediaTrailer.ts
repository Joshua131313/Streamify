import type { TMediaType } from "../../types/genericTypes";
import type { TMDBVideo } from "../../types/TMDBMediaType";
import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";



interface TMDBVideoResponse {
    result: TMDBVideo[]
}

export const useMediaTrailer = (
    id: number,
    mediaType: TMediaType,
) : [string | null, boolean, any]=> {

    const [data, loading, err] = useTMDBQuery<TMDBVideoResponse>({
        endpoint: `/${mediaType}/${id}/videos`
    });

    const trailer = data?.result?.find(v => v.site === "YouTube" && v.type === "Trailer")

    return [trailer ? `https://www.youtube.com/embed/${trailer.key}` : null, loading, err]
}