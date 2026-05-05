import { useEffect, useState } from "react"
import type { TMDBRawMovie } from "../../../types/TMDBMovieType";
import type { TStreamProviders, TStreamCategories } from "../../../types/tmdb";

interface Props {
    category?: TStreamCategories;
    provider?: TStreamProviders
    genreId?: number;
    page?: number;
    query?: string;
}

export const useMovies = (props : Props) : TMDBRawMovie[] => {
    const { category = "trending", provider, genreId, page = 1 } = props
    const [movies, setMovies] = useState<TMDBRawMovie[]>([]);

  

    return movies
}