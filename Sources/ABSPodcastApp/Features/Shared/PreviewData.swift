#if DEBUG
import Foundation

/// Sample payloads in the ABS v2.37.1 shape, for SwiftUI previews only.
enum PreviewData {
    static let podcasts: [PodcastSummary] = decode(LibraryItemsPage.self, """
    {"results":[
      {"id":"li_1","updatedAt":1,"numEpisodesIncomplete":3,
       "media":{"numEpisodes":120,"metadata":{"title":"Accidental Tech Podcast","author":"Marco, Casey, John"}}},
      {"id":"li_2","updatedAt":1,
       "media":{"numEpisodes":40,"metadata":{"title":"Backlog","author":null}}},
      {"id":"li_3","updatedAt":1,"numEpisodesIncomplete":12,
       "media":{"numEpisodes":300,"metadata":{"title":"A Podcast With a Much Longer Name Than Fits","author":"Someone"}}}
    ]}
    """).results

    static let episodeList: EpisodeListData = {
        let detail = decode(PodcastDetail.self, """
        {"id":"li_1","updatedAt":1,"media":{
          "metadata":{"title":"Accidental Tech Podcast","author":"Marco, Casey, John",
            "description":"<p>Three nerds discussing tech, Apple, programming, and loosely related matters.</p>"},
          "episodes":[
            {"id":"e3","title":"Episode 650: The Long Weekend","publishedAt":1761000000000,"duration":7380},
            {"id":"e2","title":"Episode 649: Half Way There","publishedAt":1760400000000,"duration":6900},
            {"id":"e1","title":"Episode 648: All Done","publishedAt":1759800000000,"duration":7100},
            {"id":"e0","title":"Bonus: An Episode With No Date or Length"}
          ]}}
        """)
        let progress = decode(MediaProgressResponse.self, """
        {"mediaProgress":[
          {"libraryItemId":"li_1","episodeId":"e2","duration":6900,"progress":0.45,"currentTime":3105,"isFinished":false},
          {"libraryItemId":"li_1","episodeId":"e1","duration":7100,"progress":1,"currentTime":7100,"isFinished":true}
        ]}
        """).mediaProgress
        return EpisodeListData(detail: detail, progress: EpisodeProgressIndex(progress, libraryItemId: "li_1"))
    }()

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            fatalError("Preview JSON for \(type) is invalid: \(error)")
        }
    }
}
#endif
