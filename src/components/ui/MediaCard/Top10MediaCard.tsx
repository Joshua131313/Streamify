import { Link } from "react-router-dom";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import "./MediaCard.css"

interface Props {
    media: TMDBMedia;
    rank: number;
}

export const Top10MediaCard = (props : Props) => {
    const { media, rank } = props
    return (
        <Link to={`/${media.mediaType}/${media.id}`}>
            <div className="top10-media-card media-card">
                <span className="rank-number">{rank}</span>
                <img 
                    src={`https://image.tmdb.org/t/p/original${media.poster_path}`} 
                    alt={media.title} 
                />
            </div>
        </Link>
    )
}