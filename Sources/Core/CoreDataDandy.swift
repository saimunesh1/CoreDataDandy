//
//  CoreDataDandy.swift
//  CoreDataDandy
//
//  Created by Noah Blake on 6/20/15.
//  Copyright © 2015 Fuzz Productions, LLC. All rights reserved.
//
//  This code is distributed under the terms and conditions of the MIT license.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.

import CoreData

/// `CoreDataDandy` provides an interface to the majority of the module's features, which include Core Data
/// bootstrapping, main and background-threaded context management, convenient `NSFetchRequests`,
/// database inserts, database deletes, and `NSManagedObject` deserialization.
public class CoreDataDandy {
	// MARK: - Properties -
	/// A singleton encapsulating much of CoreDataDandy's base functionality.
	private static let defaultDandy = CoreDataDandy()

	/// The default implementation of Dandy. Subclasses looking to extend or alter Dandy's functionality
	/// should override this getter and provide a new instance.
	public class var sharedDandy: CoreDataDandy {
		return defaultDandy
	}

	/// A manager of the NSManagedObjectContext, NSPersistentStore, and NSPersistentStoreCoordinator.
	/// Accessing this property directly is generaly discouraged - it is intended for use within the module alone.
	public var coordinator: PersistentStackCoordinator!

	// MARK: - Initialization-
	/// Bootstraps the application's core data stack.
	///
	/// - parameter managedObjectModelName: The name of the .xcdatamodel file
	/// - parameter completion: A completion block executed on initialization completion
	public class func wake(managedObjectModelName: String, completion: (() -> Void)? = nil) -> CoreDataDandy {
		EntityMapper.clearCache()
		sharedDandy.coordinator = PersistentStackCoordinator(managedObjectModelName: managedObjectModelName,
												persistentStoreConnectionCompletion: completion)
		return sharedDandy
	}

	// MARK: -  Deinitialization -
	/// Removes all cached data from the application without endangering future database
	/// interactions.
	public func tearDown() {
		coordinator.resetManageObjectContext()

		do {
			try NSFileManager.defaultManager().removeItemAtURL(PersistentStackCoordinator.persistentStoreURL)
		} catch {
			log(message("Failed to delete persistent store"))
		}

		coordinator.resetPersistentStore()
		EntityMapper.clearCache()
		save()
	}

	// MARK: - Inserts -
	/// Inserts a new Model from the specified entity type. In general, this function should not be invoked
	/// directly, as its incautious use is likely to lead to database leaks.
	///
	/// - parameter type: The type of Model to insert
	///
	/// - returns: A managed object if one could be inserted for the specified Entity.
	public func insert<Model: NSManagedObject>(type: Model.Type) -> Model? {
		return _insert(String(type)) as? Model
	}

	/// MARK: - Upserts -
	/// This function performs upserts differently depending on whether the Model is marked as unique or not.
	///
	/// If the Model is marked as unique (either through an @primaryKey decoration or an xcdatamode constraint), the
	/// primaryKeyValue is extracted and an upsert is performed through
	/// `upsertUnique(_:, identifiedBy:) -> NSManagedObject?`.
	///
	/// Otherwise, an insert is performed and a Model is written to from the json provided.
	///
	/// - parameter type: The type of Model to insert
	/// - parameter json: A json object to map into the returned object's attributes and relationships
	///
	/// - returns: A managed object if one could be created.
	public func upsert<Model: NSManagedObject>(type: Model.Type, from json: [String: AnyObject]) -> Model? {
		guard let entity = NSEntityDescription.forType(type) else {
			log(message("Could not retrieve NSEntityDescription for type \(type)"))
			return nil
		}

		if entity.isUnique {
			if let primaryKeyValue = entity.primaryKeyValueFromJSON(json) {
				return upsertUnique(type, identifiedBy: primaryKeyValue, from: json)
			} else {
				log(message("Could not retrieve primary key from json \(json)."))
				return nil
			}
		}

		if let managedObject = insert(type) {
			return ObjectFactory.build(managedObject, from: json)
		}

		return nil
	}

	/// Attempts to build an array Models from a json array. Through recursion, behaves identically to
	/// upsert(_:, _:) -> Model?.
	///
	/// - parameter type: The type of Model to insert
	/// - parameter json: An array to map into the returned objects' attributes and relationships
	///
	/// - returns: An array of managed objects if one could be created.
	public func batchUpsert<Model: NSManagedObject>(type: Model.Type, from json: [[String:AnyObject]]) -> [Model]? {
		var models = [Model]()
		for object in json {
			if let model = upsert(type, from: object) {
				models.append(model)
			}
		}
		return (models.count > 0) ? models: nil
	}

	// MARK: - Unique objects -
	/// Attempts to fetch a Model of the specified type matching the primary key provided.
	/// - If no property on the type's `NSEntityDescription` is marked with the @primaryKey identifier or constraint,
	/// a warning is issued and no managed object is returned.
	/// - If an object matching the primaryKey is found, it is returned. Otherwise a new object is inserted and returned.
	/// - If more than one object is fetched for this primaryKey, a warning is issued and one is returned.
	///
	/// - parameter type: The type of Model to insert.
	/// - parameter primaryKeyValue: The value of the unique object's primary key
	public func insertUnique<Model: NSManagedObject>(type: Model.Type, identifiedBy primaryKeyValue: AnyObject) -> Model? {
		return _insertUnique(String(type), identifiedBy: primaryKeyValue) as? Model
	}

	/// Invokes `upsertUnique(_:, identifiedBy:) -> Model?`, then attempts to write values from
	/// the provided JSON into the returned object.
	///
	/// - parameter type: The type of the requested entity
	/// - parameter primaryKeyValue: The value of the unique object's primary key
	/// - parameter json: A json object to map into the returned object's attributes and relationships
	///
	/// - returns: A managed object if one could be created.
	private func upsertUnique<Model: NSManagedObject>(type: Model.Type, identifiedBy primaryKeyValue: AnyObject, from json: [String: AnyObject]) -> Model? {
		if let object = insertUnique(type, identifiedBy: primaryKeyValue) {
			ObjectFactory.build(object, from: json)
			return object
		} else {
			log(message("Could not upsert managed object of type \(type), identified by \(primaryKeyValue), json \(json)."))
			return nil
		}
	}

	// MARK: - Fetches -
	/// A wrapper around NSFetchRequest.
	///
	/// - parameter type: The type of the fetched entity
	/// - parameter predicate: The predicate used to filter results
	///
	/// - throws: If the ensuing NSManagedObjectContext's executeFetchRequest() throws, the exception will be passed.
	///
	/// - returns: If the fetch was successful, the fetched Model.
	public func fetch<Model: NSManagedObject>(type: Model.Type, filterBy predicate: NSPredicate? = nil) throws -> [Model]? {
		return try _fetch(String(type), filterBy: predicate) as? [Model]
	}
	
	/// Attempts to fetch a unique Model with a primary key value matching the passed in parameter.
	///
	/// - parameter type: The type of the fetched entity
	/// - parameter primaryKeyValue: The value of unique object's primary key
	///
	/// - returns: If the fetch was successful, the fetched Model.
	public func fetchUnique<Model: NSManagedObject>(type: Model.Type, identifiedBy primaryKeyValue: AnyObject) -> Model? {
		return _fetchUnique(String(type), identifiedBy: primaryKeyValue, emitResultCountWarnings: true) as? Model
	}

	// MARK: - Saves and Deletes -
	/// Save the current state of the `NSManagedObjectContext` to disk and optionally receive notice of the save
	/// operation's completion.
	///
	/// - parameter completion: An optional closure that is invoked when the save operation complete. If the save operation
	/// 	resulted in an error, the error is returned.
	public func save(completion:((error: NSError?) -> Void)? = nil) {
		/**
		Note: http://www.openradar.me/21745663. Currently, there is no way to throw out of performBlock. If one arises,
		this code should be refactored to throw.
		*/
		if !coordinator.mainContext.hasChanges && !coordinator.privateContext.hasChanges {
			if let completion = completion {
				completion(error: nil)
			}
			return
		}
		coordinator.mainContext.performBlockAndWait({[unowned self] in
			do {
				try self.coordinator.mainContext.save()
			} catch {
				log(message( "Failed to save main context."))
				completion?(error: error as NSError)
				return
			}

			self.coordinator.privateContext.performBlock({ [unowned self] in
				do {
					try self.coordinator.privateContext.save()
					completion?(error: nil)
				}
				catch {
					log(message( "Failed to save private context."))
					completion?(error: error as NSError)
				}
				})
			})
	}

	/// Delete a managed object.
	///
	/// - parameter object: The object to be deleted.
	/// - parameter completion: An optional closure that is invoked when the deletion is complete.
	public func delete(object: NSManagedObject, completion: (() -> Void)? = nil) {
		if let context = object.managedObjectContext {
			context.performBlock({
				context.deleteObject(object)
				completion?()
			})
		}
	}
	
	// MARK: - Singletons -
	/// Attempts to singleton of a given type.
	///
	/// - parameter type: The type of the singleton
	///
	/// - returns: The singleton for this type if one could be found.
	private func singleton<Model: NSManagedObject>(type: Model.Type) -> Model? {
		return _singleton(String(type)) as? Model
	}
}
// MARK: - Convenience accessors -
/// A lazy global for more succinct access to CoreDataDandy's sharedDandy.
public let Dandy: CoreDataDandy = CoreDataDandy.sharedDandy