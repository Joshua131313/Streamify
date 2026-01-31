import "./MediaCard.css"
import "./MediaCard.css"
import { FaStar } from "react-icons/fa";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Link } from "react-router-dom";

interface Props {
    media: TMDBMedia;
}

export const MediaCard = (props: Props)  => {
    const { media } = props
    return (
       <Link to={`/${media.mediaType}/${media.id}`}>
            <div className="media-card">
                <img 
                    src={`https://image.tmdb.org/t/p/original${media.poster_path}`} 
                    alt={media.title} 
                />
                <div className="media-card-overlay"></div>
                <div className="media-info flex-col">
                    <span className="media-title">{media.title}</span>
                    <div className="flex-row sb">
                        <small>{media.mediaType}</small>
                        <div className="flex-row media-rating">
                            <FaStar className="text-red-500" />
                            <small className="rating">{media.vote_average}/10</small>
                        </div>
                    </div>
                </div>
            </div>
       </Link>
    )
}