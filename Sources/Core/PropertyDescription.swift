//
//  PropertyDescription.swift
//  CoreDataDandyTests
//
//  Created by Noah Blake on 7/3/15.
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

/// The type of a `PropertyDescription`.
///
/// - Unknown: An unknown property description type. Generally indicative of an improperly instantiated `PropertyDescription.`
/// - Attribute: Marks a property description corresponding to an attribute.
/// - Relationship: Marks a property description corresponding to an relationship.
enum PropertyType: Int {
	case unknown = 0
	case attribute
	case relationship
}

/// `PropertyDescription` provides a convenient means of accessing information necessary to map json into an
/// NSManagedObject. It encapsulates values found in `NSAttributeDescriptions` and `NSRelationshipDescriptions`, such as
/// an attribute's type or if a relationship is ordered or not.
final class PropertyDescription: NSObject {
	/// The name of of the property.
	var name = String()
	
	/// The property type: .Unknown, .Attribute, or .Relationship.
	var type = PropertyType.unknown
	
	/// The type of an attribute.
	var attributeType: NSAttributeType?
	
	/// A boolean indicating whether the property is optional or not.
	var optional = true
	
	/// The entity description of a relationship.
	var destinationEntity: NSEntityDescription?
	
	/// A boolean describing if a relationship is ordered or not. By default, false.
	var ordered = false
	
	/// A boolean describing if a relationship is toMany or not. By default, false.
	var toMany = false
	
	override init() { super.init() }
	
	/// An initializer that builds a `PropertyDescription` from either an `NSAttributeDescription` or an
	/// `NSRelationshipDescription`.
	///
	/// Note that a default object without meaningful values will be returned if neither of the above is
	convenience init(description: Any) {
		if let description = description as? NSAttributeDescription {
			self.init(attributeDescription: description)
		} else if let description = description as? NSRelationshipDescription {
			self.init(relationshipDescription: description)
		} else {
			self.init()
			log(format("Unknown property type for description: \(description)"))
		}
	}
	
	/// An initializer that builds a `PropertyDescription` by extracting relevant values from an `NSAttributeDescription`.
	fileprivate init(attributeDescription: NSAttributeDescription) {
		name = attributeDescription.name
		type = PropertyType.attribute
		attributeType = attributeDescription.attributeType
		optional = attributeDescription.isOptional
		super.init()
	}
	
	/// An initializer that builds a `PropertyDescription` by extracting relevant values from an `NSRelationshipDescription`.
	fileprivate init(relationshipDescription: NSRelationshipDescription) {
		name = relationshipDescription.name
		type = PropertyType.relationship
		destinationEntity = relationshipDescription.destinationEntity
		ordered = relationshipDescription.isOrdered
		toMany = relationshipDescription.isToMany
		optional = relationshipDescription.isOptional
		super.init()
	}
}

// MARK: - <NSCoding> -
extension PropertyDescription : NSCoding {
	convenience init?(coder aDecoder: NSCoder) {
		self.init()
		if let n = aDecoder.decodeObject(forKey: "name") as? String {
			name = n
		}
		type = PropertyType(rawValue: aDecoder.decodeInteger(forKey: "type"))!
		attributeType = NSAttributeType(rawValue: UInt(aDecoder.decodeInteger(forKey: "attributeType")))!
		ordered = aDecoder.decodeBool(forKey: "ordered")
		toMany = aDecoder.decodeBool(forKey: "toMany")
	}
	
	@objc func encode(with aCoder: NSCoder) {
		aCoder.encode(name, forKey:"name")
		aCoder.encode(type.rawValue, forKey:"type")
		if let attributeType = attributeType {
			aCoder.encode(Int(attributeType.rawValue), forKey:"attributeType")
		}
		if let destinationEntity = destinationEntity {
			aCoder.encode(destinationEntity, forKey:"destinationEntity")
		}
		aCoder.encode(ordered, forKey: "ordered")
		aCoder.encode(toMany, forKey: "toMany")
	}
	
	override var hashValue: Int {
		get {
			return "\(name)_\(type)_\(attributeType)_\(destinationEntity)_\(ordered)_\(toMany)".hashValue
		}
	}
}

// MARK: - Equality -
extension PropertyDescription {
	/// Compares the hashValue of two `PropertyDescription` objects. `PropertyDescription` objects are never considered
	/// equal to other types.
	override func isEqual(_ object: Any?) -> Bool {
		if let object = object as? PropertyDescription {
			return hashValue == object.hashValue
		} else {
			return false
		}
	}
}
