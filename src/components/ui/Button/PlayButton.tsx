import { FaPlay } from "react-icons/fa"
import { Button } from "./Button"
import type { TMediaType } from "../../../types/genericTypes";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const PlayButton = (props : Props) => {
    const { mediaType, mediaId } = props;
    console.log(mediaType)
    console.log(mediaId)
    return (
        <Button className="play-button">
            <FaPlay />
            Play
        </Button>
    )
}