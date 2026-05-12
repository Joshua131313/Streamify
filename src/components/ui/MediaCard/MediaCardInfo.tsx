import { FaStar } from "react-icons/fa";

import type {
    TMDBMedia,
    TMDBMovieMedia,
    TMDBShowMedia
} from "../../../types/TMDBMediaType";

interface Props {
    media: TMDBMedia;
}

export const MediaCardInfo = (props: Props) => {

    const { media } = props;

    const isShow =
        media.mediaType === "tv";

    const movieMedia =
        media as TMDBMovieMedia;

    const showMedia =
        media as TMDBShowMedia;

    const startDate =
        isShow
            ? showMedia.first_air_date
            : movieMedia.release_date;

    const startYear =
        startDate?.split("-")[0];

    const yearLabel = (() => {

        if (!isShow) {
            return startYear;
        }

        return startYear;

    })();

    return (
        <div className="media-card-info">

            <strong>
                {media.title}
            </strong>

            <div className="media-details">

                <span className="rating">
                    <FaStar />
                    {media.vote_average}
                </span>

                {
                    yearLabel && (
                        <>
                            <div className="dot" />

                            <span>
                                {yearLabel}
                            </span>
                        </>
                    )
                }

                <div className="dot" />

                <span>
                    {
                        media.mediaType === "movie"
                            ? "Movie"
                            : "TV Show"
                    }
                </span>

            </div>

        </div>
    );
};