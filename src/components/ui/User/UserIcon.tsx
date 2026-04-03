import { FaUser } from "react-icons/fa";
import { useAuthProvider } from "../../../context/AuthContext"
import { Button } from "../Button/Button";
import { Icon } from "../Icon/Icon";
import { Link } from "react-router-dom";


export const UserIcon = () => {
    const { user, logout } = useAuthProvider();
    if (user) {
        return (
            <div className="user-icon" onClick={logout}>
                <Icon Icon={FaUser} />
            </div>
        )
    }
    else {
        return (
            <Link to={"/login"}>
                <Button>Login</Button>
            </Link>
        )
    }
}