import { useEffect, useState } from "react"
import { type TMDBRawMovie } from "../../../types/TMDBMovieType";
import axios from "axios";
import { getTMDBEndpointByCategory } from "../../../utils/helpers";
import type { TStreamCategories, TStreamProviders } from "../../../types/tmdb";

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

    return movies
}