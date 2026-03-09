import { Link } from "react-router-dom";
import { TMDBImg } from "../../ui/TMDBImg/TMDBImg";
import { FaUserCircle } from "react-icons/fa";


interface Props {
    name: string;
    subtitle?: string;
    profilePath: string | null;
    id: number;
}

export const CreditCard = (props: Props) => {
    const { name, subtitle, profilePath, id } = props;

    return (
        <Link to={`/person/${id}`}>
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
        </Link>
    )
}