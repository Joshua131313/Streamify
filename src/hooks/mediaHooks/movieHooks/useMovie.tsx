import { type TMDBRawMovie } from "../../../types/TMDBMovieType";
import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeMovie } from "../../../utils/normalizeTMDB";
import type { TMDBMovieMedia } from "../../../types/TMDBMediaType";
import type { UseQueryResult } from "@tanstack/react-query";

type UseMovieResult = UseQueryResult<TMDBRawMovie> & {
    movie: TMDBMovieMedia | null,
}

export const useMovie = ({movieId} : {movieId: string}) : UseMovieResult => {

    const query = useTMDBQuery<TMDBRawMovie>({
        endpoint: `/movie/${movieId}`,
        params: {
            append_to_response: "videos,credits,images"
        }
    })
    return {
        ...query,
        movie: query.data ? normalizeMovie(query.data) : null
    }
}