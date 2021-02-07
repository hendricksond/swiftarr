import Vapor
import Fluent

// MARK: - Functions

extension FezPost {
    /// Converts a `FezPost` model to a version omitting data that is not for public
    /// consumption.
    func convertToData() throws -> FezPostData {
        return try FezPostData(
            postID: self.requireID(),
            authorID: self.author.requireID(),
            text: self.text,
            image: self.image
        )
    }
}

extension EventLoopFuture where Value: FezPost {
    /// Convers a `Future<FezPost>` to a `Futured<FezPostData>`. This extension provides
    /// the convenience of simply using `post.convertToData)` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData() -> EventLoopFuture<FezPostData> {
        return self.flatMapThrowing {
            (fezPost) in
            return try fezPost.convertToData()
        }
    }
}

// fezposts can be filtered by author and content
extension FezPost: ContentFilterable {
    /// Checks if a `FezPost` contains any of the provided array of muting strings, returning true if it does
    ///
    /// - Parameters:
    ///   - mutewords: The list of strings on which to filter the post.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func containsMutewords(using mutewords: [String]) -> Bool {
        for word in mutewords {
            if self.text.range(of: word, options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }
    
    /// Checks if a `Twarrt` contains any of the provided array of muting strings, returning
    /// either the original twarrt or `nil` if there is a match.
    ///
    /// - Parameters:
    ///   - post: The `Event` to filter.
    ///   - mutewords: The list of strings on which to filter the post.
    ///   - req: The incoming `Request` on whose event loop this needs to run.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func filterMutewords(using mutewords: [String]?) -> FezPost? {
        if let mutewords = mutewords {
			for word in mutewords {
				if self.text.range(of: word, options: .caseInsensitive) != nil {
					return nil
				}
			}
		}
        return self
    }
    
}