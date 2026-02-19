import { FaStar } from "react-icons/fa"
import { MediaBadge } from "./MediaBadge"
import "./MediaMetaBadges.css"
import { HiOutlineCalendar } from "react-icons/hi2";
import { TMDB_GENRES, type TGenre } from "../../../data/TMDBGenres";
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { Fragment } from "react/jsx-runtime";

export interface MediaMetaBadgesProps {
    genresLimit?: number;
    genre_ids: number[] | undefined;
    vote_average: number;
    date: string;
    mediaType?: TMediaType;
}

export const MediaMetaBadges = (props: MediaMetaBadgesProps) => {
    const { genre_ids, vote_average, date, genresLimit = genre_ids?.length, mediaType } = props

    const genresRow = genre_ids?.slice(0, genresLimit).map(genreId => {
        const El = mediaType ? Link : Fragment
        return (
            <El
                 key={genreId}
                 to={`/discover?media=${mediaType}&genre=${genreId}`}
             >
                <MediaBadge 
                    text={TMDB_GENRES.find((x : TGenre)=> x.value === genreId.toString())?.label ?? ""}
                />
            </El>
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