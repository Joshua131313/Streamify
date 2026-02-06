import { Link } from "react-router-dom";
import type { TEpisode } from "../../../types/TMDBShowType"
import { TMDBImg } from "../TMDBImg/TMDBImg";
import "./MediaCard.css"
import { Icon } from "../Icon/Icon";
import { FaClock, FaPlay, FaStar } from "react-icons/fa";
import { MediaBadge } from "../MediaMetaBadges/MediaBadge";

interface Props {
    episode: TEpisode;
}

export const EpisodeCard = (props: Props) => {
    const { episode } = props;
    return (
        <Link 
            to={`?play&season=${episode.season_number}&episode=${episode.episode_number}`} 
            className="episode-card"
        >
            <div className="still-container">
                <MediaBadge className="time" Icon={FaClock} text={`${episode.runtime?.toString() ?? 0} min`}/>
                <MediaBadge className="rating" Icon={FaStar} text={`${episode.vote_average.toFixed(1)}/10`}/>
                <TMDBImg 
                    type="still"
                    size="w185"
                    path={episode.still_path ?? ""}
                />
                <Icon Icon={FaPlay} />
                <span className="episode-number">{episode.episode_number}</span>
            </div>
            <div className="episode-info">
                <strong>{episode.name}</strong>
                <small>{episode.overview}</small>
                {/* <div className="episode-badges">
                    <MediaBadge Icon={FaClock} text={`${episode.runtime?.toString() ?? 0} min`}/>
                    <MediaBadge Icon={FaStar} text={`${episode.vote_average.toFixed(1)}/10`}/>
                </div> */}
            </div>
        </Link>
    )

}