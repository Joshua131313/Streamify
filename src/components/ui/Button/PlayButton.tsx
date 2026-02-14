import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const PlayButton = (props : Props) => {
    const { mediaType, mediaId } = props;
    const { get } = useLocalStorage();
    
    const playUrl = () => {
        const base = `/${mediaType}/${mediaId}?play`
        if(mediaType === "movie") {
            return base;
        }
        else {
            const lastEpisode = get(mediaId.toString(), {season: 1, episode: 1});
            return base + `&season=${lastEpisode.season}&episode=${lastEpisode.episode}`
        }
    }

    return (
        <Link to={playUrl()}>
            <Button className="play-button">
                <FaPlay />
                Play
            </Button>
        </Link>
    )
}