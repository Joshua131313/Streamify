import type { TLabelValue, TStreamCategories } from "../types/tmdb";
import { providers } from "../data/providers";
import { getMainGenres } from "../data/TMDBGenres";

const MOVIE_TV_TABS = [ 
    { label: "Movies", value: "movie" },
    { label: "Series", value: "tv" }   
] 
export const getCategoryTabs = (category : TStreamCategories) : TLabelValue[] => {
    switch(category) {
        case "top10":
        return MOVIE_TV_TABS;
        case "trending": 
        return MOVIE_TV_TABS;
        case "provider":
            return providers.map(p => ({
                label: p.name,
                value: p.provider
            }))
        case "top_rated":
            return MOVIE_TV_TABS;
        case "byGenre":
            return getMainGenres("movie");

    }
}