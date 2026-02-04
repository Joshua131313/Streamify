import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/tmdb";
import { Link } from "react-router-dom";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const PlayButton = (props : Props) => {
    const { mediaType, mediaId } = props;

    return (
        <Link to={`/${mediaType}/${mediaId}?play`}>
            <Button className="play-button">
                <FaPlay />
                Play
            </Button>
        </Link>
    )
}