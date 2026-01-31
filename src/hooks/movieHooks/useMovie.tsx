import { useEffect, useState } from "react"
import axios from "axios";
import { TMDBNullMovie, type TMDBRawMovie } from "../../types/TMDBMovieType";
import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeMovie } from "../../utils/normalizeTMDB";
import type { TMDBMovieMedia } from "../../types/TMDBMediaType";


export const useMovie = ({movieId} : {movieId: string}) : [TMDBMovieMedia | null, boolean, any] => {

    const [data, loading, err] = useTMDBQuery<TMDBRawMovie>({
        endpoint: `/movie/${movieId}`,
        params: {
            append_to_response: "videos,credits,images"
        }
    })
    console.log('movie', data)
    const movie = data ? normalizeMovie(data) : null; 
    return [movie, loading, err]
}