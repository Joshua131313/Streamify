import { useEffect, useState } from "react"
import type { TMDBRawMovie, TMDBNullMovie } from "../../types/TMDBMovieType";
import axios from "axios";
import type { TStreamProviders, TStreamCategories } from "../../types/genericTypes";
import { getTMDBEndpointByCategory } from "../../utils/helpers";

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
                setMovies(res.results);
            })
            .catch(err => console.log(err));

    }, [category, genreId, provider, page]);

    return movies
}