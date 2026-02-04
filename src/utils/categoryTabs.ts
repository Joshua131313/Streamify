import type { TStreamCategories } from "../types/tmdb";
import { providers } from "../data/providers";
import { TMDB_MAIN_GENRES } from "../data/TMDBGenres";
export type TTab = {
    text: string;
    value: string;
}  
const MOVIE_TV_TABS = [ 
    { text: "Movies", value: "movie" },
    { text: "Series", value: "tv" }   
] 
export const getCategoryTabs = (category : TStreamCategories) : TTab[] => {
    switch(category) {
        case "top10":
        return MOVIE_TV_TABS;
        case "trending": 
        return MOVIE_TV_TABS;
        case "provider":
            return providers.map(p => ({
                text: p.name,
                value: p.provider
            }))
        case "top_rated":
            return MOVIE_TV_TABS;
        case "byGenre":
            return TMDB_MAIN_GENRES

    }
}