import { Icon } from "../Icon/Icon"
import type { TMDBMedia } from "../../../types/TMDBMediaType"
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage"
import { BsBookmark, BsBookmarkFill } from "react-icons/bs"
import { useEffect, useState } from "react"


export const SaveMediaButton = ({media} : {media: TMDBMedia}) => {
    const { has, remove, append } = useLocalStorage();
    const [isSaved, setIsSaved] = useState(false);

    const handleClick = () => {
        if(isSaved) {
            setIsSaved(false);
            remove<TMDBMedia>("savedMedia", (m) => m.id === media.id);
        }
        else {
            setIsSaved(true);
            append("savedMedia", media);
        }
    }

    useEffect(()=> {
        setIsSaved(has<TMDBMedia>("savedMedia", media, (m) => m.id === media.id));
    }, [media.id])


    return (
        <Icon 
            className="save-media-button"
            Icon={isSaved ? BsBookmarkFill : BsBookmark} 
            onClick={handleClick}
        />
    )
}