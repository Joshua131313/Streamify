import { FaPlusCircle } from "react-icons/fa"
import { Button } from "./Button"
import { Link } from "react-router-dom";
import type { TMediaType } from "../../../types/genericTypes";

interface Props {
    mediaType: TMediaType;
    mediaId: number;
}

export const SeeMoreButton = (props : Props) => {
    const { mediaType, mediaId } = props;
    return (
        <Link to={`/${mediaType}/${mediaId}`}>
            <Button className="secondary">
                <FaPlusCircle />
                See More
            </Button>
        </Link>
    )
}