import type { TLabelValue, TStreamCategories } from "../types/tmdb";
import { providers } from "../data/providers";
import { getMainGenres } from "../data/TMDBGenres";

const MOVIE_TV_TABS = [ 
    { label: "Movies", value: "movie" },
    { label: "Series", value: "tv" }   
] 
export const getCategoryTabs = (category : TStreamCategories) : TLabelValue[] => {
    switch(category) {
        case "provider":
            return providers.map(p => ({
                label: p.name,
                value: p.provider
            }))
        case "top_10":
        case "trending": 
        case "top_rated":
        case "for_you":
            return MOVIE_TV_TABS;
        case "by_genre":
            return getMainGenres("movie");

    }
}