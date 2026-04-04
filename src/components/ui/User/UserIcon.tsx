import { FaBookmark, FaCog, FaHistory, FaSignOutAlt, FaUser } from "react-icons/fa";
import { useAuthProvider } from "../../../context/AuthContext"
import { Button } from "../Button/Button";
import { Icon } from "../Icon/Icon";
import { Link, useNavigate } from "react-router-dom";
import { Dropdown } from "../Dropdown/Dropdown";
import "./UserIcon.css"

export const UserIcon = () => {
    const { user, logout } = useAuthProvider();
    const navigate = useNavigate()
    if (user) {
        return (
            <Dropdown
                dropdownOptions={[
                    {
                        icon: FaBookmark,
                        key: "saved-media",
                        onClick: () => navigate("/saved-media"),
                        value: "Saved media"
                    },
                    {
                        icon: FaHistory,
                        key: "history",
                        onClick: () => navigate("/history"),
                        value: "Watch history"
                    },
                    {
                        icon: FaSignOutAlt,
                        key: "signout",
                        onClick: () => logout(),
                        value: "Sign out"
                    },
                    {
                        icon: FaCog,
                        key: "preferences",
                        onClick: () => navigate("/settings"),
                        value: "Preferences"
                    },
                ]}
                title="Profile"
                className="user-icon"
            >
                <Icon Icon={FaUser} />
            </Dropdown>
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