import { FaBookmark, FaCog, FaHistory, FaSignOutAlt, FaUser, FaSignInAlt, FaUserPlus } from "react-icons/fa";
import { useAuthProvider } from "../../../context/AuthContext";
import { Icon } from "../Icon/Icon";
import { useNavigate } from "react-router-dom";
import { Dropdown } from "../Dropdown/Dropdown";
import "./UserIcon.css";
import { getInitials } from "../../../utils/helpers";
import { AppImg } from "../ImgProxy/AppImg";

export const UserIcon = () => {
    const { user, logout } = useAuthProvider();
    const navigate = useNavigate();

    const isLoggedIn = !!user;

    const commonOptions = [
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
        }
    ];

    const loggedInOptions = [
        ...commonOptions,
        {
            icon: FaCog,
            key: "preferences",
            onClick: () => navigate("/settings"),
            value: "Preferences"
        },
        {
            icon: FaSignOutAlt,
            key: "signout",
            onClick: () => logout(),
            value: "Sign out"
        }
    ];

    const guestOptions = [
        ...commonOptions,
        {
            icon: FaSignInAlt,
            key: "login",
            onClick: () => navigate("/login"),
            value: "Login"
        },
        {
            icon: FaUserPlus,
            key: "register",
            onClick: () => navigate("/register"),
            value: "Register"
        }
    ];

    return (
        <Dropdown
            dropdownOptions={isLoggedIn ? loggedInOptions : guestOptions}
            title={isLoggedIn ? (user.name ?? "Profile") : "Guest"}
            subTitle={isLoggedIn ? (user.email ?? "") : ""}
            className="user-icon"
        >
            {
                user?.image ? (
                    <AppImg src={user.image} alt="user" className="user-img" />
                ) : user?.name ? (
                    <span className="user-initials">{getInitials(user.name)}</span>
                ) : (
                    <Icon Icon={FaUser} />
                )
            }
            {/* <Icon Icon={FaUser} /> */}
        </Dropdown>
    );
};