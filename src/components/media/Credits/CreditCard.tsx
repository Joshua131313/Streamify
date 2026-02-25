import { TMDBImg } from "../../ui/TMDBImg/TMDBImg";
import { FaUserCircle } from "react-icons/fa";


interface Props {
    name: string;
    subtitle?: string;
    profilePath: string | null;
}

export const CreditCard = (props: Props) => {
    const { name, subtitle, profilePath } = props;

    return (
        <a target="_blank" href={`https://www.google.com/search?q=${name}`}>
            <div className="credit-card">
                {profilePath ?
                    <TMDBImg type="profile" size="w185" path={profilePath} />
                    : 
                    <FaUserCircle className="user-circle"/>
                }
                <div className="credit-info">
                    <strong>{name}</strong>
                    {subtitle && <small>{subtitle}</small>}
                </div>
            </div>
        </a>
    )
}