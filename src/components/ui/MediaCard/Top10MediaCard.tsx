import { Link } from "react-router-dom";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import "./MediaCard.css"
import { TMDBImg } from "../ImgProxy/TMDBImg";
import { MediaCardInfo } from "./MediaCardInfo";

interface Props {
    media: TMDBMedia;
    rank: number;
}

export const Top10MediaCard = (props: Props) => {
    const { media, rank } = props
    return (
        <Link to={`/${media.mediaType}/${media.id}`}>
            <div className="top10-media-card media-card">
                <div className="media-card-content">
                    <span className="rank-number"><p>TOP</p>{String(rank).padStart(2, "0")}</span>

                    <TMDBImg
                        path={media.poster_path}
                        type="poster"
                        size="w500"
                    />
                </div>
                <MediaCardInfo media={media} />

            </div>
        </Link>
    )
}