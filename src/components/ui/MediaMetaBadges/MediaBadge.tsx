import type { IconType } from "react-icons";

interface Props {
    Icon?: IconType;
    text: string;
    className?: string;
}

export const MediaBadge = (props: Props) => {
    const { Icon, text, className } = props; 
    return (
        <div className={`media-badge ${className}`}>
            {
                Icon && <Icon className="media-badge-icon" />
            }
            {text}
        </div>
    )
}