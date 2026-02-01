import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/genericTypes";
import { Link } from "react-router-dom";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const PlayButton = (props : Props) => {
    const { mediaType, mediaId } = props;
    console.log(mediaType)
    console.log(mediaId)
    return (
        <Link to={`/${mediaType}/${mediaId}?play`}>
            <Button className="play-button">
                <FaPlay />
                Play
            </Button>
        </Link>
    )
}