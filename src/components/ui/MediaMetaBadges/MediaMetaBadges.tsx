import { FaStar } from "react-icons/fa"
import { MediaBadge } from "./MediaBadge"
import { TMDB_MOVIE_GENRES } from "../../../data/TMDBGenres";
import "./MediaMetaBadges.css"
import { HiOutlineCalendar } from "react-icons/hi2";

export interface MediaMetaBadgesProps {
    genresLimit?: number;
    genre_ids: number[];
    vote_average: number;
    date: string;
}

export const MediaMetaBadges = (props: MediaMetaBadgesProps) => {
    const { genre_ids, vote_average, date, genresLimit = genre_ids.length } = props
    const genresRow = genre_ids?.slice(0, genresLimit).map(genreId => {
        return (
            <MediaBadge 
                text={TMDB_MOVIE_GENRES.find(x=> x.value === genreId.toString())?.text ?? ""}
            />
        )
    })
    console.log("assd", genre_ids)
    return (
        <div className="media-meta-badges">
            <div className="general-badges">
                <MediaBadge 
                    Icon={FaStar}
                    text={`${vote_average}/10`}
                    className="rating"
                />
                <MediaBadge 
                    Icon={HiOutlineCalendar} 
                    text={new Date(date).getFullYear().toString()}
                />
            </div>
            <div className="genres-badges">
                {genresRow}
            </div>
        </div>
    )
}