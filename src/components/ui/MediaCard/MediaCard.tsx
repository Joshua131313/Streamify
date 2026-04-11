import "./MediaCard.css"
import "./MediaCard.css"
import { FaStar } from "react-icons/fa";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Link, useNavigate } from "react-router-dom";
import { TMDBImg } from "../TMDBImg/TMDBImg";
import { SaveMediaButton } from "../Button/SaveMediaButton";
import { PlayButton } from "../Button/PlayButton";

interface Props {
    media: TMDBMedia;
}

export const MediaCard = (props: Props) => {
    const { media } = props;
    return (
        <>
        <div className="media-card" >
            <Link  to={`/${media.mediaType}/${media.id}`} className="media-card-content">
                <TMDBImg type="poster" size="w342" path={media.poster_path ?? ""} />
                <div className="media-card-overlay"></div>
                <div className="media-info flex-col">
                    <span className="media-title">{media.title}</span>
                    <div className="flex-row sb">
                        <small>{media.mediaType === "movie" ? "Movie" : "Series"}</small>
                        <div className="flex-row media-rating">
                            <FaStar className="text-red-500" />
                            <small className="rating">{media.vote_average}/10</small>
                        </div>
                    </div>
                </div>
            </Link>
            <PlayButton
                variant="icon"
                mediaId={media.id}
                mediaType={media.mediaType}
            />
            <SaveMediaButton media={media} />
        </div>
        <Link to={`/${media.mediaType}/${media.id}`} className="mobile-media-card">
                <TMDBImg type="poster" size="w342" path={media.poster_path ?? ""} />
        </Link>
        </>
    )
}