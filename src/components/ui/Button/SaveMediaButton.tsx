import { Icon } from "../Icon/Icon";
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { BsBookmark, BsBookmarkFill } from "react-icons/bs";
import { useSavedMediaContext } from "../../../context/SavedMediaContext";

export const SaveMediaButton = ({ media }: { media: TMDBMedia }) => {
    const { isSaved, addMedia, removeMedia } = useSavedMediaContext();

    const saved = isSaved(media);

    const handleClick = () => {
        if (saved) {
            removeMedia(media);
        } else {
            addMedia(media);
        }
    };

    return (
        <Icon
            className="save-media-button"
            Icon={saved ? BsBookmarkFill : BsBookmark}
            onClick={handleClick}
        />
    );
};