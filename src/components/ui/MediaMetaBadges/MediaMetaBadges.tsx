import { FaStar } from "react-icons/fa"
import { MediaBadge } from "./MediaBadge"
import "./MediaMetaBadges.css"
import { HiOutlineCalendar } from "react-icons/hi2";
import { TMDB_GENRES, type TGenre } from "../../../data/TMDBGenres";

export interface MediaMetaBadgesProps {
    genresLimit?: number;
    genre_ids: number[] | undefined;
    vote_average: number;
    date: string;
}

export const MediaMetaBadges = (props: MediaMetaBadgesProps) => {
    const { genre_ids, vote_average, date, genresLimit = genre_ids?.length } = props
    const genresRow = genre_ids?.slice(0, genresLimit).map(genreId => {
        return (
            <MediaBadge 
                key={genreId}
                text={TMDB_GENRES.find((x : TGenre)=> x.value === genreId.toString())?.label ?? ""}
            />
        )
    })
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