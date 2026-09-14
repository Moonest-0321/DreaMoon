import Foundation
import SwiftData

/// V5 deliberately does not migrate the released organization feature into
/// the new power graph. The old model types remain in the technical schema so
/// stores can open safely, then their rows are removed in one idempotent pass.
@MainActor
enum V5DataCleanup {
    static func removeLegacyOrganizations(in context: ModelContext) throws {
        let identities = try context.fetch(FetchDescriptor<OrganizationIdentityHistory>())
        let memberships = try context.fetch(FetchDescriptor<CharacterOrganization>())
        let organizations = try context.fetch(FetchDescriptor<Organization>())

        for identity in identities { context.delete(identity) }
        for membership in memberships { context.delete(membership) }
        for organization in organizations { context.delete(organization) }

        // CharacterSummary is retained for the other summary selectors. Only
        // clear the removed organization selector; do not remove characters.
        let summaries = try context.fetch(FetchDescriptor<CharacterSummary>())
        for summary in summaries {
            summary.organizationIdentity = nil
            if summary.alias == nil,
               summary.ability == nil,
               summary.psychology == nil,
               summary.relationship == nil {
                context.delete(summary)
            }
        }
        try context.save()
    }
}
