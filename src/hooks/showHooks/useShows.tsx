import { useEffect, useState } from "react"
import { type TMDBRawMovie } from "../../types/TMDBMovieType";
import axios from "axios";
import { getTMDBEndpointByCategory } from "../../utils/helpers";
import type { TStreamCategories, TStreamProviders } from "../../types/genericTypes";

interface Props {
    category?: TStreamCategories;
    provider?: TStreamProviders;
    genreId?: number;
    page?: number;
    query?: string;
}

export const useShows = (props : Props) : TMDBRawMovie[] => {
    const { category = "trending", provider, genreId, page = 1 } = props
    const [movies, setMovies] = useState<TMDBRawMovie[]>([]);

    useEffect(() => {
        const endpoint = getTMDBEndpointByCategory(
            "movie",
            category,
            genreId?.toString(),
            provider
        )
        axios
            .get(
                `https://api.themoviedb.org/3${endpoint}&page=${page}&api_key=${import.meta.env.VITE_TMDB_API_KEY}`
            )
            .then(resp => {
                let res = resp.data ?? [];
                if(category === 'top10') {
                    res = res.slice(0, 10);
                }
                setMovies(res);
            });
    }, [category, genreId, provider, page]);

    return movies
}